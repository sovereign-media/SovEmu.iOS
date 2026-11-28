import Foundation
import SovEmuKit
import Synchronization
import WebRTC

/// A connection to one game session: receive-only video and audio, plus the unordered,
/// no-retransmit `input` DataChannel, which `InputLoop` sends on. Signalling is one POST of the
/// complete offer (non-trickle), exactly as the web and Android clients do.
///
/// Made off the main thread while the game loads (its peer connection takes a moment), then used
/// on it. `@unchecked Sendable` for that handover: after `init`, its own state is touched on the
/// main thread only (the callbacks, `link`, `pipeline`, `closed`), but for what WebRTC's threads
/// reach, which is under a lock (`rtts`, `FrameTap`, `FrameLatency`) or a Mutex (`gathered`).
final class Stream: NSObject, @unchecked Sendable {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        // The audio engine module records only once a local audio track starts, and SovEmu sends
        // none. The platform default's voice-processing unit opens the microphone just to play,
        // which needs a microphone permission (a TV kills the app without one) for audio that
        // only ever comes in.
        return RTCPeerConnectionFactory(
            audioDeviceModuleType: .audioEngine, bypassVoiceProcessing: true,
            encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory(),
            audioProcessingModule: nil)
    }()

    /// Most audio packets the jitter buffer may hold: 150 ms at the server's 10 ms a packet,
    /// which holds the buffer's own target to about 110 ms, as SovEmu.Android's.
    private static let audioBufferMaxPackets: Int32 = 15

    private let api: SovEmuAPI
    private let videoView: RTCVideoRenderer
    /// What this device decodes and shows, sent with the offer: the server picks the codec by it.
    private let capabilities: ClientCapabilities
    /// Read on the main thread (`UIDevice`), and handed in.
    private let clientName: String
    private var pc: RTCPeerConnection!
    /// The input channel, for `InputLoop`.
    private(set) var channel: RTCDataChannel!
    /// ICE gathering finished, or the wait for it gave up.
    private let gathered = OneShot()
    /// Samples the connection's stats for the worker, on the main thread.
    private var statsTimer: Timer?
    private var sampler = StatsSampler()
    private var closed = false

    /// Called on the main thread.
    var onState: ((RTCPeerConnectionState) -> Void)?
    /// How the worker makes this stream (`0x82`), the latest the worker sent; nil until it
    /// sends one (an older server never does). Set on the main thread, for a stats overlay.
    private(set) var pipeline: WireProtocol.Pipeline?
    var onPipeline: ((WireProtocol.Pipeline) -> Void)?
    /// The worker's check of the connection before the stream starts (`0x83`, #243), the latest
    /// it sent; nil until it has (an older worker never does). Set on the main thread.
    private(set) var link: WireProtocol.Link?
    /// The check moved on: the loading screen follows it. Called on the main thread.
    var onLink: ((WireProtocol.Link) -> Void)?
    /// The worker changed the stream's quality: the notice to show (`qualityNotice`). Called on
    /// the main thread.
    var onQuality: ((WireProtocol.QualityNotice) -> Void)?
    /// The game's first picture reached the screen. Called once, on the main thread.
    var onFirstFrame: (() -> Void)?
    /// Each second's stats, as sent to the worker, and the reading they came from. Called on the
    /// main thread.
    var onStats: ((WireProtocol.Stats, StatsReading) -> Void)?

    /// Button to frame, measured from the worker's acks and the frames shown after them.
    let frameLatency = FrameLatency()
    /// Watches the frames reaching the screen, beside the video view.
    private let tap = FrameTap()
    /// The video track in the view (main thread only). Kept: an `RTCVideoTrack` removes its
    /// renderers when it is freed, and the stream's wrapper of it is not kept by anything else.
    private var videoTrack: RTCVideoTrack?
    private let rttLock = NSLock()
    /// The last input round trips, in ms (send, the worker applies it on a frame, its ack).
    private var rtts: [Int64] = []
    private static let rttWindow = 32

    /// Frames shown so far (read once a second, to notice a picture that stops).
    var frames: Int64 { tap.frames }
    /// The recent input round trips, in ms.
    var inputRtts: [Int64] { rttLock.withLock { rtts } }

    /// Builds the peer connection, its transceivers and the input channel: any thread.
    init(api: SovEmuAPI, iceServers: [IceServer], videoView: RTCVideoRenderer, capabilities: ClientCapabilities,
         clientName: String) {
        self.api = api
        self.videoView = videoView
        self.capabilities = capabilities
        self.clientName = clientName
        super.init()
        tap.latency = frameLatency
        tap.onFirst = { [weak self] in DispatchQueue.main.async { self?.onFirstFrame?() } }
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // One transport for video, audio and the channel, RTCP on it too: fewer candidate pairs
        // to check, and the worker offers nothing else.
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        // Sound a little late beats sound that drifts further behind the picture: the buffer is
        // capped, and catches up quickly after a burst.
        config.audioJitterBufferMaxPackets = Self.audioBufferMaxPackets
        config.audioJitterBufferFastAccelerate = true
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

    /// Offers to the session `sessionId` and connects. Cancelled (the player left, or the
    /// connection is being replaced), it throws `CancellationError` and starts nothing; the
    /// caller closes the stream.
    func connect(sessionId: String) async throws {
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
        // Non-trickle: wait for every candidate (or 1.5 s) before sending the offer. Gathering
        // may have finished already, before the wait began.
        if pc.iceGatheringState == .complete { gathered.fire() }
        let timeout = Task { [gathered] in
            // Cancelled once gathering finishes: the wait is over either way.
            try? await Task.sleep(for: .milliseconds(1500))
            gathered.fire()
        }
        await gathered.wait()
        timeout.cancel()
        try Task.checkCancellation()
        let local = pc.localDescription?.sdp ?? offer.sdp
        let answer = try await api.offer(sessionId: sessionId, sdp: local, client: clientName, capabilities: capabilities)
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        try await MainActor.run {
            // Closed meanwhile (`close` runs on the main thread): nothing may start after it.
            guard !self.closed else { throw CancellationError() }
            self.startStats()
        }
    }

    /// Sends this client's view of the stream to the worker once a second from the moment the
    /// channel opens: before any video, while the worker checks the connection, the round trip
    /// and the path it judges the link by (#243); then, while it plays, how this device keeps up,
    /// for the worker lowers the video bitrate for one that does not, which its estimate of the
    /// connection cannot see.
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
                    self.onStats?(stats, reading)
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
        let playout = all.first { $0.type == "media-playout" }?.values ?? [:]
        // The transport's selected pair, as the web's `selectedPair`; else the nominated one
        // that succeeded.
        let selectedId = all.first { $0.type == "transport" && $0.values["selectedCandidatePairId"] != nil }?
            .values["selectedCandidatePairId"] as? String
        let pair = (selectedId.flatMap { report.statistics[$0]?.values } ?? all.first {
            $0.type == "candidate-pair" && ($0.values["nominated"] as? NSNumber)?.boolValue == true
                && $0.values["state"] as? String == "succeeded"
        }?.values) ?? [:]
        func candidate(_ key: String) -> IceCandidateStats? {
            guard let id = pair[key] as? String, let values = report.statistics[id]?.values,
                  let type = values["candidateType"] as? String else { return nil }
            return IceCandidateStats(candidateType: type, protocol: values["protocol"] as? String,
                                     relayProtocol: values["relayProtocol"] as? String)
        }
        func num(_ values: [String: NSObject], _ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        var reading = StatsReading(
            at: report.timestamp_us / 1_000_000,
            bytesReceived: num(video, "bytesReceived") ?? 0,
            jitterBufferDelay: num(video, "jitterBufferDelay") ?? 0,
            jitterBufferEmittedCount: num(video, "jitterBufferEmittedCount") ?? 0,
            totalDecodeTime: num(video, "totalDecodeTime") ?? 0,
            framesDecoded: num(video, "framesDecoded") ?? 0,
            framesPerSecond: num(video, "framesPerSecond"),
            width: num(video, "frameWidth").map { Int($0) },
            height: num(video, "frameHeight").map { Int($0) },
            packetsLost: StatsReading.packetsLost(video: num(video, "packetsLost"), audio: num(audio, "packetsLost")),
            framesDropped: num(video, "framesDropped").map { Int($0) },
            networkRttMs: num(pair, "currentRoundTripTime").map { $0 * 1000 },
            decoder: video["decoderImplementation"] as? String,
            hasVideo: !video.isEmpty,
            local: candidate("localCandidateId"),
            remote: candidate("remoteCandidateId"))
        reading.audioJitterBufferDelay = num(audio, "jitterBufferDelay") ?? 0
        reading.audioJitterBufferTargetDelay = num(audio, "jitterBufferTargetDelay") ?? 0
        reading.audioJitterBufferEmittedCount = num(audio, "jitterBufferEmittedCount") ?? 0
        reading.audioPlayoutDelay = num(playout, "totalPlayoutDelay") ?? 0
        reading.audioPlayoutSamples = num(playout, "totalSamplesCount") ?? 0
        return reading
    }

    private func send(_ data: Data) {
        channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

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

    /// On the main thread; once is enough, more is harmless.
    func close() {
        guard !closed else { return }
        closed = true
        gathered.fire()
        statsTimer?.invalidate()
        channel?.close()
        pc?.close()
    }
}

extension Stream: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { gathered.fire() }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async { self.onState?(newState) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if let track = transceiver.receiver.track as? RTCVideoTrack { attach(track) }
    }

    /// The stream's video track, typed as one: LiveKit's build hands the receiver's track back as
    /// a plain `RTCMediaStreamTrack`, which `didStartReceivingOn` cannot cast.
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first { attach(track) }
    }

    /// Shows `track` in the video view and counts its frames, once whichever callback finds it.
    private func attach(_ track: RTCVideoTrack) {
        DispatchQueue.main.async {
            guard self.videoTrack == nil else { return }
            self.videoTrack = track
            track.add(self.videoView)
            track.add(self.tap)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

extension Stream: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}
    /// The worker sends acks (`0x81`), its pipeline (`0x82`) and its check of the connection
    /// (`0x83`); anything else, or a message that does not decode, is ignored.
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard buffer.isBinary else { return }
        if let ack = WireProtocol.decodeAck(buffer.data) {
            acked(ack)
            return
        }
        if let link = WireProtocol.decodeLink(buffer.data) {
            DispatchQueue.main.async { if LinkLabels.supersedes(self.link, link) { self.setLink(link) } }
            return
        }
        guard let pipeline = WireProtocol.decodePipeline(buffer.data) else { return }
        DispatchQueue.main.async {
            // The check's result comes again with the pipeline: a lost `0x83` is not missed.
            if let link = pipeline.link, self.link != link, LinkLabels.supersedes(self.link, link) { self.setLink(link) }
            guard pipeline != self.pipeline else { return }
            let notice = WireProtocol.qualityNotice(before: self.pipeline, now: pipeline)
            self.pipeline = pipeline
            if let notice { self.onQuality?(notice) }
            self.onPipeline?(pipeline)
        }
    }
}

extension Stream {
    /// On the main thread.
    fileprivate func setLink(_ link: WireProtocol.Link) {
        self.link = link
        onLink?(link)
    }
}

/// Something that happens once, and a wait for it: `fire` may come first, more than once, or from
/// any thread, and the waiter is resumed exactly once. (A continuation resumed twice, as the ICE
/// wait's could be when gathering finished as its timeout did, crashes the app.)
private final class OneShot: Sendable {
    private struct State {
        var fired = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func fire() {
        let waiter = state.withLock { s -> CheckedContinuation<Void, Never>? in
            guard !s.fired else { return nil }
            s.fired = true
            defer { s.waiter = nil }
            return s.waiter
        }
        waiter?.resume()
    }

    /// Returns once `fire` has been called, at once if it was already.
    func wait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let now = state.withLock { s in
                if s.fired { return true }
                s.waiter = c
                return false
            }
            if now { c.resume() }
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
