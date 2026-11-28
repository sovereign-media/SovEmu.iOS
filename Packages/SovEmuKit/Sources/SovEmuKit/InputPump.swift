import Foundation
import Synchronization

// What the input channel carries, and when, as SovEmu.Android's InputPump.kt and InputSequence.kt
// (same names, timings and test cases): plain logic, driven by the app's input loop.

/// The input pump's timings (`InputPump`).
public enum InputPumpDefaults {
    /// Held input is sent again this often, so the worker knows it is still held.
    public static let heartbeatMs: Int64 = 100
    /// A change is sent again this long after, and again after twice this (about a frame each):
    /// the channel neither orders nor retransmits, and a lost change would otherwise wait for
    /// the next heartbeat. The worker drops the copies, which carry the same number.
    public static let resendMs: Int64 = 16
    /// Copies of each change after the first.
    public static let resends = 2
}

/// The numbers of a game's input packets, carried across reconnects: the worker remembers the
/// last number it took and drops anything no newer, so numbers started again with a new
/// connection would leave the game deaf to input.
public final class InputSequence: Sendable {
    private let numbers = Mutex((input: UInt32(0), analog: UInt32(0)))

    public init() {}

    /// The next input packet's number (wrapping as the worker's comparison expects).
    public func nextInput() -> UInt32 {
        numbers.withLock {
            $0.input &+= 1
            return $0.input
        }
    }

    /// The next stick packet's number.
    public func nextAnalog() -> UInt32 {
        numbers.withLock {
            $0.analog &+= 1
            return $0.analog
        }
    }
}

/// One reading of every controller (SovEmu.Android's `InputMixer.Snapshot`): each port's
/// RetroPad buttons and sticks, from port 0 to the highest in use, and the hotkeys held.
public struct InputReading: Equatable, Sendable {
    public var ports: [UInt16]
    /// As long as `ports`, or shorter: a missing stick is centred.
    public var analog: [WireProtocol.Analog]
    public var fastForward: Bool
    public var rewind: Bool

    public init(ports: [UInt16] = [0], analog: [WireProtocol.Analog] = [.centred], fastForward: Bool = false,
                rewind: Bool = false) {
        (self.ports, self.analog, self.fastForward, self.rewind) = (ports, analog, fastForward, rewind)
    }

    /// Nothing held: what the game is sent while the app is not in the foreground.
    public static func released(ports: Int) -> InputReading {
        InputReading(ports: Array(repeating: 0, count: max(1, ports)), analog: [])
    }
}

/// Decides what the input channel carries (`0x01` buttons, `0x02` hotkeys, `0x03` sticks) from
/// each reading of the controllers, and when to look again.
///
/// Buttons and hotkeys go on any change and every `heartbeatMs`; sticks on any change and,
/// while one is off-centre, at the same rate. A change is sent again `resends` times, a frame
/// apart, with the same number (a stick coming back to centre included), so one lost packet
/// costs a frame rather than a heartbeat. A change is stamped with the time of the input event
/// that made it, when known, so the round trip measured from its ack includes the hop from the
/// event to the pump. Ports in use only grow during a session, so a player who disconnects is
/// sent released rather than left holding what they last pressed.
///
/// Not thread-safe: one thread (the app's input queue) ticks it.
public final class InputPump {
    private let sequence: InputSequence
    private let send: (Data) -> Void
    private var count = 1
    private var sent: [UInt16] = []
    private var sentHotkeys: UInt8 = 0
    private var lastSend = Int64.min / 2
    private var sentAnalog: [WireProtocol.Analog] = [.centred]
    private var lastAnalogSend = Int64.min / 2

    /// The last change's packets and when to send them again.
    private var resend: [Data] = []
    private var resendsLeft = 0
    private var resendAt: Int64 = 0
    private var analogResend: Data?
    private var analogResendsLeft = 0
    private var analogResendAt: Int64 = 0

    public init(sequence: InputSequence, send: @escaping (Data) -> Void) {
        (self.sequence, self.send) = (sequence, send)
    }

    /// Sends what `reading` calls for at `nowMs` (a monotonic clock), and returns how long until
    /// the pump should look again, unless an input changes first. `paused`: the in-game menu is
    /// open, so the game gets nothing held and is told to pause. `stampMs` is now on the clock
    /// acks are measured on (the 32-bit `client_time_ms`), and `eventMs` the time on that clock
    /// of the input event that last changed something, when known.
    @discardableResult
    public func tick(_ reading: InputReading, paused: Bool, nowMs: Int64, stampMs: Int64, eventMs: Int64? = nil) -> Int64 {
        count = max(count, paused ? 1 : min(WireProtocol.maxPorts, reading.ports.count))
        let buttons = (0..<count).map { i in paused || i >= reading.ports.count ? 0 : reading.ports[i] }
        let fastForward = !paused && reading.fastForward
        let rewind = !paused && reading.rewind
        let hotkeys: UInt8 = (fastForward ? 1 : 0) | (rewind ? 2 : 0) | (paused ? 4 : 0)
        let changed = hotkeys != sentHotkeys || buttons != sent
        if changed || nowMs - lastSend >= InputPumpDefaults.heartbeatMs {
            // A change carries its event's time; a heartbeat, now. An event older than a
            // heartbeat is not this change's.
            let stamp = eventMs.flatMap { changed && $0 <= stampMs && stampMs - $0 < InputPumpDefaults.heartbeatMs ? $0 : nil }
                ?? stampMs
            var packets = [WireProtocol.encodeInput(seq: sequence.nextInput(), clientTimeMs: UInt32(truncatingIfNeeded: stamp),
                                                    ports: buttons)]
            if hotkeys != sentHotkeys || hotkeys != 0 {
                packets.append(WireProtocol.encodeHotkeys(fastForward: fastForward, rewind: rewind, pause: paused))
            }
            packets.forEach(send)
            sent = buttons
            sentHotkeys = hotkeys
            lastSend = nowMs
            if changed {
                resend = packets
                resendsLeft = InputPumpDefaults.resends
                resendAt = nowMs + InputPumpDefaults.resendMs
            }
        } else if resendsLeft > 0 && nowMs >= resendAt {
            resend.forEach(send)
            resendsLeft -= 1
            resendAt = nowMs + InputPumpDefaults.resendMs
        }

        let sticks = (0..<count).map { i in paused || i >= reading.analog.count ? WireProtocol.Analog.centred : reading.analog[i] }
        let analogChanged = sticks != sentAnalog
        let offCentre = sticks.contains { $0 != .centred }
        if analogChanged || (offCentre && nowMs - lastAnalogSend >= InputPumpDefaults.heartbeatMs) {
            let packet = WireProtocol.encodeAnalog(seq: sequence.nextAnalog(), ports: sticks)
            send(packet)
            sentAnalog = sticks
            lastAnalogSend = nowMs
            if analogChanged {
                analogResend = packet
                analogResendsLeft = InputPumpDefaults.resends
                analogResendAt = nowMs + InputPumpDefaults.resendMs
            }
        } else if analogResendsLeft > 0 && nowMs >= analogResendAt {
            analogResend.map(send)
            analogResendsLeft -= 1
            analogResendAt = nowMs + InputPumpDefaults.resendMs
        }

        var next = lastSend + InputPumpDefaults.heartbeatMs
        if offCentre { next = min(next, lastAnalogSend + InputPumpDefaults.heartbeatMs) }
        if resendsLeft > 0 { next = min(next, resendAt) }
        if analogResendsLeft > 0 { next = min(next, analogResendAt) }
        return max(1, next - nowMs)
    }
}
