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
    private var pc: RTCPeerConnection!
    private var channel: RTCDataChannel!
    private var gathered: CheckedContinuation<Void, Never>?
    private var timer: DispatchSourceTimer?
    private var seq: UInt32 = 0
    private var sent: UInt16 = .max
    private var sentHotkeys: UInt8 = 0
    private var lastSend = Date.distantPast

    /// While true (a menu is open) the game sees nothing pressed.
    var suspended = false
    var onState: ((RTCPeerConnectionState) -> Void)?
    var onMenu: (() -> Void)?
    private var menuHeld = false

    init(api: SovEmuAPI, sessionId: String, iceServers: [IceServer], controller: Controller, videoView: RTCVideoRenderer) {
        self.api = api
        self.sessionId = sessionId
        self.controller = controller
        self.videoView = videoView
        super.init()
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
        let answer = try await api.offer(sessionId: sessionId, SessionDescription(type: "offer", sdp: local))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer.sdp)) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        startPump()
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
        let buttons = suspended ? 0 : reading.buttons
        let hotkeys: UInt8 = suspended ? 0 : (reading.fastForward ? 1 : 0) | (reading.rewind ? 2 : 0)
        let now = Date()
        guard buttons != sent || hotkeys != sentHotkeys || now.timeIntervalSince(lastSend) > 0.1 else { return }
        seq &+= 1
        send(WireProtocol.encodeInput(seq: seq, clientTimeMs: now32(), ports: [buttons]))
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

    private func now32() -> UInt32 { UInt32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1000)) }

    func close() {
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
            DispatchQueue.main.async { track.add(self.videoView) }
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
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {}
}
