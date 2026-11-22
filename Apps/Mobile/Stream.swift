import Foundation
import SovEmuKit
import WebRTC

/// A connection to one game session: receive-only video and audio, plus the unordered,
/// no-retransmit `input` DataChannel. Signalling is one POST of the complete offer (non-trickle),
/// exactly as the web and Android clients do.
final class Stream: NSObject {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private let api: SovEmuAPI
    private let sessionId: String
    private let controller: Controller
    private let videoView: RTCVideoRenderer
    /// Read on the main thread (`UIDevice`), when the stream is made.
    private let clientName = ClientEvents.clientName
    private var pc: RTCPeerConnection!
    private var channel: RTCDataChannel!
    private var gathered: CheckedContinuation<Void, Never>?
    private var timer: DispatchSourceTimer?
    /// Samples the connection's stats for the worker, on the main thread.
    private var statsTimer: Timer?
    private var sampler = StatsSampler()
    private var closed = false
    private var seq: UInt32 = 0
    private var sent: [UInt16] = []
    private var sentHotkeys: UInt8 = 0
    private var lastSend = Date.distantPast
    private var analogSeq: UInt32 = 0
    private var sentAnalog: [WireProtocol.Analog] = [.centred]
    private var lastAnalogSend = Date.distantPast
    /// The most ports sent this session: a player whose controller went away is then sent as
    /// released and centred rather than dropped.
    private var portCount = 1

    /// While true (a menu is open) the game sees nothing pressed.
    var suspended = false
    var onState: ((RTCPeerConnectionState) -> Void)?
    var onMenu: (() -> Void)?
    /// How the worker makes this stream (`0x82`), the latest the worker sent; nil until it
    /// sends one (an older server never does). Set on the main thread, for a stats overlay.
    private(set) var pipeline: WireProtocol.Pipeline?
    var onPipeline: ((WireProtocol.Pipeline) -> Void)?
    /// The worker changed the stream's quality: the notice to show (`qualityNotice`). Called on
    /// the main thread.
    var onQuality: ((WireProtocol.QualityNotice) -> Void)?
    /// The game's first picture reached the screen. Called once, on the main thread.
    var onFirstFrame: (() -> Void)?
    /// Each second's stats, as sent to the worker. Called on the main thread.
    var onStats: ((WireProtocol.Stats) -> Void)?
    private var menuHeld = false

    /// Button to frame, measured from the worker's acks and the frames shown after them.
    let frameLatency = FrameLatency()
    /// Watches the frames reaching the screen, beside the video view.
    private let tap = FrameTap()
    private let rttLock = NSLock()
    /// The last input round trips, in ms (send, the worker applies it on a frame, its ack).
    private var rtts: [Int64] = []
    private static let rttWindow = 32

    /// Frames shown so far (read once a second, to notice a picture that stops).
    var frames: Int64 { tap.frames }
    /// The recent input round trips, in ms.
    var inputRtts: [Int64] { rttLock.withLock { rtts } }

    init(api: SovEmuAPI, sessionId: String, iceServers: [IceServer], controller: Controller, videoView: RTCVideoRenderer) {
        self.api = api
        self.sessionId = sessionId
        self.controller = controller
        self.videoView = videoView
        super.init()
        tap.latency = frameLatency
        tap.onFirst = { [weak self] in DispatchQueue.main.async { self?.onFirstFrame?() } }
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        let recvOnly = RTCRtpTransceiverInit()
        recvOnly.direction = .recvOnly
        pc.addTransceiver(of: .video, init: recvOnly)
        pc.addTransceiver(of: .audio, init: recvOnly)
        let dc = RTCDataChannelConfiguration()
        dc.isOrdered = false
        dc.maxRetransmits = 0
        channel = pc.dataChannel(forLabel: WireProtocol.inputChannel, configuration: dc)
        channel.delegate = self
    }

    func connect() async throws {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) } else { cont.resume(throwing: error ?? APIError(status: 0, message: "no offer")) }
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        // Non-trickle: wait for every candidate (or 1.5 s) before sending the offer.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await withCheckedContinuation { self.gathered = $0 } }
            group.addTask { try? await Task.sleep(for: .milliseconds(1500)) }
            await group.next()
            group.cancelAll()
            self.gathered?.resume()
            self.gathered = nil
        }
        let local = pc.localDescription?.sdp ?? offer.sdp
        let answer = try await api.offer(sessionId: sessionId, sdp: local, client: clientName)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        startPump()
        await MainActor.run { self.startStats() }
    }

    /// Sends this client's view of the stream to the worker once a second while it plays: the
    /// worker lowers the video bitrate for a device that is not keeping up, which its estimate
    /// of the connection cannot see.
    private func startStats() {
        guard !closed else { return }
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.closed, self.channel.readyState == .open else { return }
            self.pc.statistics { report in
                let reading = Self.reading(report)
                DispatchQueue.main.async {
                    guard !self.closed, self.channel.readyState == .open else { return }
                    let stats = self.sampler.sample(reading, client: self.clientName, inputRtts: self.inputRtts,
                                                    inputToFrameMs: self.frameLatency.medianMs())
                    self.send(WireProtocol.encodeStats(stats))
                    self.onStats?(stats)
                }
            }
        }
    }

    private static func reading(_ report: RTCStatisticsReport) -> StatsReading {
        let all = report.statistics.values
        func inbound(_ kind: String) -> [String: NSObject] {
            all.first { $0.type == "inbound-rtp" && $0.values["kind"] as? String == kind }?.values ?? [:]
        }
        let video = inbound("video")
        let audio = inbound("audio")
        let pair = all.first {
            $0.type == "candidate-pair" && ($0.values["nominated"] as? NSNumber)?.boolValue == true
                && $0.values["state"] as? String == "succeeded"
        }?.values ?? [:]
        func num(_ values: [String: NSObject], _ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        return StatsReading(
            at: report.timestamp_us / 1_000_000,
            bytesReceived: num(video, "bytesReceived") ?? 0,
            jitterBufferDelay: num(video, "jitterBufferDelay") ?? 0,
            jitterBufferEmittedCount: num(video, "jitterBufferEmittedCount") ?? 0,
            totalDecodeTime: num(video, "totalDecodeTime") ?? 0,
            framesDecoded: num(video, "framesDecoded") ?? 0,
            framesPerSecond: num(video, "framesPerSecond"),
            width: num(video, "frameWidth").map { Int($0) },
            height: num(video, "frameHeight").map { Int($0) },
            packetsLost: Int((num(video, "packetsLost") ?? 0) + (num(audio, "packetsLost") ?? 0)),
            framesDropped: num(video, "framesDropped").map { Int($0) },
            networkRttMs: num(pair, "currentRoundTripTime").map { $0 * 1000 },
            decoder: video["decoderImplementation"] as? String)
    }

    /// Sends the controller state every 4 ms when it changes and at least every 100 ms.
    private func startPump() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "sovemu.input"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(4))
        timer.setEventHandler { [weak self] in self?.pump() }
        timer.resume()
        self.timer = timer
    }

    private func pump() {
        let reading = controller.read()
        if reading.menu && !menuHeld { DispatchQueue.main.async { self.onMenu?() } }
        menuHeld = reading.menu
        guard channel.readyState == .open else { return }
        // Every player from 1 to the highest in use; a menu shows the game nothing pressed.
        portCount = max(portCount, reading.ports.count)
        let pads = reading.ports + [UInt16](repeating: 0, count: portCount - reading.ports.count)
        let sticks = reading.analog + [WireProtocol.Analog](repeating: .centred, count: portCount - reading.analog.count)
        let buttons = suspended ? pads.map { _ in 0 } : pads
        let hotkeys: UInt8 = suspended ? 0 : (reading.fastForward ? 1 : 0) | (reading.rewind ? 2 : 0)
        let now = Date()
        // Sticks: on change, and as a heartbeat while off-centre.
        let analog = suspended ? sticks.map { _ in .centred } : sticks
        let offCentre = analog.contains { $0 != .centred }
        if analog != sentAnalog || (offCentre && now.timeIntervalSince(lastAnalogSend) > 0.1) {
            analogSeq &+= 1
            send(WireProtocol.encodeAnalog(seq: analogSeq, ports: analog))
            sentAnalog = analog
            lastAnalogSend = now
        }
        guard buttons != sent || hotkeys != sentHotkeys || now.timeIntervalSince(lastSend) > 0.1 else { return }
        seq &+= 1
        send(WireProtocol.encodeInput(seq: seq, clientTimeMs: now32(), ports: buttons))
        if hotkeys != sentHotkeys || hotkeys != 0 {
            send(WireProtocol.encodeHotkeys(fastForward: hotkeys & 1 != 0, rewind: hotkeys & 2 != 0))
        }
        sent = buttons
        sentHotkeys = hotkeys
        lastSend = now
    }

    private func send(_ data: Data) {
        channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    private func now32() -> UInt32 { Self.now32() }

    /// The app's 32-bit millisecond clock, the one `client_time_ms` carries.
    static func now32() -> UInt32 { UInt32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1000)) }

    /// An ack for an input: its round trip, and the start of a button-to-frame measurement.
    private func acked(_ ack: WireProtocol.Ack) {
        let now = Int64(Self.now32())
        let rtt = (now - Int64(ack.clientTimeMs)) & 0xffff_ffff
        if rtt < FrameLatency.maxPlausibleMs {
            rttLock.withLock {
                rtts.append(rtt)
                if rtts.count > Self.rttWindow { rtts.removeFirst(rtts.count - Self.rttWindow) }
            }
        }
        frameLatency.ackArrived(clientTimeMs: Int64(ack.clientTimeMs), nowMs: now)
    }

    func close() {
        closed = true
        statsTimer?.invalidate()
        timer?.cancel()
        channel?.close()
        pc?.close()
    }
}

extension Stream: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            gathered?.resume()
            gathered = nil
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async { self.onState?(newState) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if let track = transceiver.receiver.track as? RTCVideoTrack {
            DispatchQueue.main.async {
                track.add(self.videoView)
                track.add(self.tap)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

extension Stream: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    /// The worker sends acks (`0x81`) and its pipeline (`0x82`); anything else, or a message that
    /// does not decode, is ignored.
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard buffer.isBinary else { return }
        if let ack = WireProtocol.decodeAck(buffer.data) {
            acked(ack)
            return
        }
        guard let pipeline = WireProtocol.decodePipeline(buffer.data) else { return }
        DispatchQueue.main.async {
            guard pipeline != self.pipeline else { return }
            let notice = WireProtocol.qualityNotice(before: self.pipeline, now: pipeline)
            self.pipeline = pipeline
            if let notice { self.onQuality?(notice) }
            self.onPipeline?(pipeline)
        }
    }
}

/// A second renderer on the video track: it draws nothing, and counts the frames reaching the
/// screen, says when the first one does, and ends a button-to-frame measurement with each.
/// Frames arrive on WebRTC's render thread.
private final class FrameTap: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int64 = 0
    var latency: FrameLatency?
    var onFirst: (() -> Void)?

    var frames: Int64 { lock.withLock { count } }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let first = lock.withLock {
            count += 1
            return count == 1
        }
        latency?.frameDelivered(timestampNs: frame.timeStampNs, nowMs: Int64(Stream.now32()))
        if first { onFirst?() }
    }
}
