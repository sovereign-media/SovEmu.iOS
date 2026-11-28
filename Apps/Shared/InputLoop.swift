// The player's input, as SovEmu.Android's Stream pump over `InputPump`: reads the controllers
// from the moment the player appears (so Select+Start or Home opens the menu while the game
// loads), and sends what SovEmuKit's `InputPump` decides on the current connection's channel.
// It is woken by the input itself (GameController's handlers, the touch controls), not polled:
// between changes it sleeps until the pump's next copy or heartbeat. It outlives each
// connection: a reconnect hands it the new channel, and the packet numbers carry on
// (`InputSequence`).

import Foundation
import SovEmuKit
import Synchronization
import WebRTC

/// `@unchecked Sendable`: the pump, its channel, `menuHeld` and the timer's schedule are touched
/// only on `queue`; what the main thread sets (`suspended`, `inactive`, the channel) is under
/// `shared`'s Mutex, as is whether the loop has started.
final class InputLoop: @unchecked Sendable {
    private struct Shared {
        var suspended = false
        var inactive = false
        var channel: RTCDataChannel?
        var started = false
    }

    private let controller: Controller
    private let sequence = InputSequence()
    private let queue = DispatchQueue(label: "sovemu.input", qos: .userInteractive)
    private let shared = Mutex(Shared())
    /// Wakes the loop when the pump next needs to look: made with the loop, so the queue never
    /// sees it change; resumed by `start`, cancelled by `stop`.
    private let timer: DispatchSourceTimer
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
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.tick() }
    }

    deinit {
        // A timer never resumed must be resumed before it is freed, or GCD traps.
        if !shared.withLock({ $0.started }) { timer.resume() }
        timer.cancel()
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

    /// The longest sleep: the pump's heartbeat, and how soon an input channel that opens is
    /// noticed, or an input GameController sent no event for.
    private static let idleMs = InputPumpDefaults.heartbeatMs

    /// Starts reading, on every input change and at least every `idleMs`. On the main thread.
    func start() {
        guard !shared.withLock({ s in defer { s.started = true }; return s.started }) else { return }
        timer.schedule(deadline: .now())
        timer.resume()
        controller.observe(on: queue) { [weak self] eventMs in self?.tick(eventMs: eventMs) }
    }

    /// On the main thread.
    func stop() {
        controller.stopObserving()
        timer.cancel()
        attach(nil)
    }

    /// On `queue`: reads, sends what the pump says, and sleeps until it next needs to look.
    /// `eventMs`: when the input that woke it happened, on the `client_time_ms` clock.
    private func tick(eventMs: Int64? = nil) {
        let (suspended, inactive, channel) = shared.withLock { ($0.suspended, $0.inactive, $0.channel) }
        let wait = send(suspended: suspended, inactive: inactive, channel: channel, eventMs: eventMs)
        timer.schedule(deadline: .now() + .milliseconds(Int(min(wait, Self.idleMs))))
    }

    /// How long until the pump needs to look again.
    private func send(suspended: Bool, inactive: Bool, channel: RTCDataChannel?, eventMs: Int64?) -> Int64 {
        let open = channel?.readyState == .open
        // With the menu open the game is sent only the pause, and the menu reads the controllers
        // itself: no read here. A press held as it closes is not a new one.
        let reading: Controller.Reading
        if suspended {
            menuHeld = true
            reading = Controller.Reading(ports: [0], analog: [.centred], fastForward: false, rewind: false, menu: true)
        } else {
            reading = controller.read()
            if reading.menu && !menuHeld { DispatchQueue.main.async { self.onMenu?() } }
            menuHeld = reading.menu
        }
        guard open, let channel else { return Self.idleMs }
        if channel !== pumpChannel {
            pump = InputPump(sequence: sequence) { channel.sendData(RTCDataBuffer(data: $0, isBinary: true)) }
            pumpChannel = channel
        }
        let input = inactive
            ? InputReading.released(ports: reading.ports.count)
            : InputReading(ports: reading.ports, analog: reading.analog, fastForward: reading.fastForward,
                           rewind: reading.rewind)
        return pump?.tick(input, paused: suspended, nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000),
                          stampMs: Int64(Stream.now32()), eventMs: eventMs) ?? Self.idleMs
    }
}
