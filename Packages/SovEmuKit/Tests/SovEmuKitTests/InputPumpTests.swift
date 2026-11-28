import Foundation
import Testing
@testable import SovEmuKit

/// What the input channel carries, and when, from the controllers' readings: the same cases as
/// SovEmu.Android's InputPumpTest.
struct InputPumpTests {
    private final class Sent: @unchecked Sendable {
        // One test's thread only.
        var packets: [[UInt8]] = []
    }

    private let sent = Sent()
    private let pump: InputPump
    private let a: UInt16 = 1 << 8

    init() {
        let sent = self.sent
        pump = InputPump(sequence: InputSequence()) { sent.packets.append([UInt8]($0)) }
    }

    private func le32(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    private func seq(_ b: [UInt8]) -> UInt32 { le32(b, 2) }
    private func stamp(_ b: [UInt8]) -> UInt32 { le32(b, 6) }
    private var inputs: [[UInt8]] { sent.packets.filter { $0[0] == 0x01 } }
    private var sticks: [[UInt8]] { sent.packets.filter { $0[0] == 0x03 } }

    @discardableResult
    private func tick(_ reading: InputReading, _ now: Int64, eventMs: Int64? = nil, paused: Bool = false) -> Int64 {
        pump.tick(reading, paused: paused, nowMs: now, stampMs: now, eventMs: eventMs)
    }

    @Test func aPressIsSentAtOnceStampedWithItsEventThenTwiceMoreWithItsNumber() {
        tick(InputReading(), 1_000)
        sent.packets.removeAll()
        let pressed = InputReading(ports: [a])
        let wait = tick(pressed, 1_010, eventMs: 1_004)
        #expect(inputs.count == 1)
        #expect(stamp(inputs[0]) == 1_004, "the event's time, not the send's")
        #expect(wait == InputPumpDefaults.resendMs, "looks again for the copy")
        tick(pressed, 1_010 + InputPumpDefaults.resendMs)
        tick(pressed, 1_010 + 2 * InputPumpDefaults.resendMs)
        tick(pressed, 1_010 + 3 * InputPumpDefaults.resendMs)
        #expect(inputs.count == 3)
        #expect(Set(inputs.map(seq)).count == 1, "copies carry the same number")
    }

    @Test func heldInputIsSentAgainEveryHeartbeatStampedNow() {
        let held = InputReading(ports: [a])
        tick(held, 0)
        sent.packets.removeAll()
        // Nothing changed: no copies once they are done, then the heartbeat.
        let wait = tick(held, 2 * InputPumpDefaults.resendMs + 1)
        sent.packets.removeAll()
        tick(held, InputPumpDefaults.heartbeatMs, eventMs: 1)
        #expect(inputs.count == 1)
        #expect(stamp(inputs[0]) == UInt32(InputPumpDefaults.heartbeatMs))
        #expect(wait <= InputPumpDefaults.heartbeatMs)
    }

    @Test func withNothingToDoItSleepsUntilTheHeartbeat() {
        // The first reading is sent, and its copies; then nothing until the heartbeat.
        tick(InputReading(), 0)
        tick(InputReading(), InputPumpDefaults.resendMs)
        tick(InputReading(), 2 * InputPumpDefaults.resendMs)
        #expect(tick(InputReading(), 50) == InputPumpDefaults.heartbeatMs - 50)
    }

    @Test func aStickComingBackToCentreIsSentThreeTimes() {
        tick(InputReading(analog: [WireProtocol.Analog(lx: 20_000)]), 0)
        sent.packets.removeAll()
        tick(InputReading(), 10)
        tick(InputReading(), 10 + InputPumpDefaults.resendMs)
        tick(InputReading(), 10 + 2 * InputPumpDefaults.resendMs)
        #expect(sticks.count == 3)
        #expect(Set(sticks.map(seq)).count == 1)
        // Centred, no stick heartbeat.
        sent.packets.removeAll()
        tick(InputReading(), 10 + 10 * InputPumpDefaults.heartbeatMs)
        #expect(sticks.isEmpty)
    }

    @Test func aSecondPlayerJoiningIsAChange() {
        tick(InputReading(), 0)
        sent.packets.removeAll()
        tick(InputReading(ports: [0, 0], analog: []), 5)
        #expect(inputs.count == 1)
        #expect(inputs[0][10] == 2)
    }

    @Test func pausedTheGameIsSentNothingHeldAndToldToPause() {
        let held = InputReading(ports: [a], fastForward: true)
        tick(held, 0)
        sent.packets.removeAll()
        tick(held, 5, paused: true)
        #expect(inputs[0][11] == 0 && inputs[0][12] == 0)
        let hotkeys = sent.packets.first { $0[0] == 0x02 }
        #expect(hotkeys?[2] == 4)
    }

    @Test func aNewConnectionCarriesOnTheGamesPacketNumbers() {
        // The worker remembers the last number it took across a reconnect, and drops anything
        // no newer: numbers started again would leave the game deaf to input.
        let sequence = InputSequence()
        let first = (0..<3).map { _ in sequence.nextInput() }
        let afterReconnect = sequence.nextInput()
        #expect(first == [1, 2, 3])
        #expect(afterReconnect > first[2])
        #expect(sequence.nextAnalog() == 1)
    }

    @Test func aPlayerWhoseControllerWentAwayIsSentReleased() {
        // Ports only grow: player 2 is sent as nothing held, not left holding the last press.
        tick(InputReading(ports: [0, a], analog: []), 0)
        sent.packets.removeAll()
        tick(InputReading(ports: [0], analog: []), 5)
        #expect(inputs.count == 1)
        #expect(inputs[0][10] == 2 && inputs[0][13] == 0 && inputs[0][14] == 0)
    }
}
