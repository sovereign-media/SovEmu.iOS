// The player's input, as SovEmu.Android's Stream pump over `InputPump`: reads the controllers
// from the moment the player appears (so Select+Start or Home opens the menu while the game
// loads), and sends what SovEmuKit's `InputPump` decides on the current connection's channel.
// It outlives each connection: a reconnect hands it the new channel, and the packet numbers
// carry on (`InputSequence`).

import Foundation
import SovEmuKit
import Synchronization
import WebRTC

/// `@unchecked Sendable`: the pump, its channel and `menuHeld` are touched only on `queue`; what
/// the main thread sets (`suspended`, `inactive`, the channel) is under `shared`'s Mutex; the
/// timer is made and cancelled on the main thread only.
final class InputLoop: @unchecked Sendable {
    private struct Shared {
        var suspended = false
        var inactive = false
        var channel: RTCDataChannel?
    }

    private let controller: Controller
    private let sequence = InputSequence()
    private let queue = DispatchQueue(label: "sovemu.input", qos: .userInteractive)
    private let shared = Mutex(Shared())
    private var timer: DispatchSourceTimer?
    /// On `queue`: the pump for the channel it sends on, made again for each new channel so a
    /// new connection is sent everything at once.
    private var pump: InputPump?
    private var pumpChannel: RTCDataChannel?
    private var menuHeld = false

    /// A controller asked for the menu (Select+Start, Home). Set before `start`; called on the
    /// main thread.
    var onMenu: (() -> Void)?

    init(controller: Controller) {
        self.controller = controller
    }

    /// While true (a menu is open) the game sees nothing pressed, and is paused.
    var suspended: Bool {
        get { shared.withLock { $0.suspended } }
        set { shared.withLock { $0.suspended = newValue } }
    }

    /// While true (the app is not in the foreground: Home or TV pressed, Control Center, a
    /// system alert) the game sees nothing pressed. Going out, the release is sent at once: an
    /// app suspended with a button held went silent, and the worker let go only after its
    /// half-second lapse, the button held all that time (SovEmu.iOS#43). As SovEmu.Android's
    /// `Controller.lostFocus`, it does not pause: the in-game menu does that.
    var inactive: Bool {
        get { shared.withLock { $0.inactive } }
        set {
            let went = shared.withLock { s in
                defer { s.inactive = newValue }
                return newValue && !s.inactive
            }
            if went { queue.async { self.tick() } }
        }
    }

    /// Sends on `channel` from now on (nil: nothing is sent).
    func attach(_ channel: RTCDataChannel?) {
        shared.withLock { $0.channel = channel }
    }

    /// Reads the controllers every 4 ms. On the main thread.
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(4))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// On the main thread.
    func stop() {
        timer?.cancel()
        timer = nil
        attach(nil)
    }

    /// On `queue`.
    private func tick() {
        let reading = controller.read()
        if reading.menu && !menuHeld { DispatchQueue.main.async { self.onMenu?() } }
        menuHeld = reading.menu
        let (suspended, inactive, channel) = shared.withLock { ($0.suspended, $0.inactive, $0.channel) }
        guard let channel, channel.readyState == .open else { return }
        if channel !== pumpChannel {
            pump = InputPump(sequence: sequence) { channel.sendData(RTCDataBuffer(data: $0, isBinary: true)) }
            pumpChannel = channel
        }
        let input = inactive
            ? InputReading.released(ports: reading.ports.count)
            : InputReading(ports: reading.ports, analog: reading.analog, fastForward: reading.fastForward,
                           rewind: reading.rewind)
        pump?.tick(input, paused: suspended, nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000),
                   stampMs: Int64(Stream.now32()))
    }
}
