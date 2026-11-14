import Foundation
import Testing
@testable import SovEmuKit

/// The same vectors as `input_layout_is_stable` in SovEmu.Protocol, protocol.test.ts and
/// SovEmu.Android's ProtocolTest.
struct ProtocolTests {
    @Test func encodesInputLikeTheRustReference() {
        let bytes = [UInt8](WireProtocol.encodeInput(seq: 0x0403_0201, clientTimeMs: 0x0807_0605, ports: [0x0a09]))
        #expect(bytes == [0x01, 1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 0x09, 0x0a])
    }

    @Test func encodesHotkeysLikeTheRustReference() {
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: true, rewind: true)) == [0x02, 1, 0b11])
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: true, rewind: false)) == [0x02, 1, 0b01])
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: false, rewind: true)) == [0x02, 1, 0b10])
    }

    @Test func encodesAnalogLikeTheRustReference() {
        // `analog_layout_is_stable_and_round_trips` in SovEmu.Protocol.
        let a = WireProtocol.Analog(lx: -32768, ly: 32767, rx: 1, ry: -2, l2: 0, r2: 0x1234)
        let bytes = [UInt8](WireProtocol.encodeAnalog(seq: 0x0403_0201, ports: [a]))
        #expect(bytes == [0x03, 1, 1, 2, 3, 4, 1, 0x00, 0x80, 0xff, 0x7f, 1, 0, 0xfe, 0xff, 0, 0, 0x34, 0x12])
        let clamped = [UInt8](WireProtocol.encodeAnalog(seq: 0, ports: [WireProtocol.Analog(lx: 40000)]))
        #expect(Array(clamped[7...8]) == [0xff, 0x7f])
        #expect(WireProtocol.Analog.stick(0.1) == 0)
        #expect(WireProtocol.Analog.stick(1) == 32767)
        #expect(WireProtocol.Analog.stick(-1) == -32767)
    }

    @Test func decodesTheRustReferenceAck() {
        let ack = WireProtocol.decodeAck(Data([0x81, 1, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]))
        #expect(ack == WireProtocol.Ack(seq: 1, clientTimeMs: 2, frame: 3))
    }

    @Test func rejectsOtherMessages() {
        #expect(WireProtocol.decodeAck(Data([0x81, 1])) == nil)
        #expect(WireProtocol.decodeAck(Data([0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
        #expect(WireProtocol.decodeAck(Data([0x81, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
    }

    @Test func capsPortsAndNumbersButtonsLikeLibretro() {
        #expect(WireProtocol.encodeInput(seq: 1, clientTimeMs: 0, ports: [1, 2, 3, 4, 5]).count == 19)
        #expect(RetroButton.b.bit == 1)
        #expect(RetroButton.start.bit == 1 << 3)
        #expect(RetroButton.a.bit == 1 << 8)
    }
}
