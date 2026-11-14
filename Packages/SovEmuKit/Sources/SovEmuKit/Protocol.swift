import Foundation

/// The input channel's wire format, mirroring SovEmu.Protocol (`src/input.rs`) byte for byte.
/// `ProtocolTests` uses the same vectors as the Rust, TypeScript and Kotlin tests; change all
/// four together.
public enum WireProtocol {
    public static let inputVersion: UInt8 = 1
    public static let inputChannel = "input"
    public static let maxPorts = 4

    static let typeInput: UInt8 = 0x01
    static let typeHotkeys: UInt8 = 0x02
    static let typeAck: UInt8 = 0x81

    public static func encodeInput(seq: UInt32, clientTimeMs: UInt32, ports: [UInt16]) -> Data {
        let ports = ports.prefix(maxPorts)
        var out = Data([typeInput, inputVersion])
        out.append(contentsOf: withUnsafeBytes(of: seq.littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: clientTimeMs.littleEndian, Array.init))
        out.append(UInt8(ports.count))
        for state in ports {
            out.append(contentsOf: withUnsafeBytes(of: state.littleEndian, Array.init))
        }
        return out
    }

    public static func encodeHotkeys(fastForward: Bool, rewind: Bool) -> Data {
        Data([typeHotkeys, inputVersion, (fastForward ? 1 : 0) | (rewind ? 2 : 0)])
    }

    public struct Ack: Equatable, Sendable {
        public let seq: UInt32
        public let clientTimeMs: UInt32
        public let frame: UInt32
    }

    /// Decodes an ack, or returns nil for anything else.
    public static func decodeAck(_ data: Data) -> Ack? {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, bytes[0] == typeAck, bytes[1] == inputVersion else { return nil }
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        return Ack(seq: u32(2), clientTimeMs: u32(6), frame: u32(10))
    }
}

/// RetroPad buttons (libretro `RETRO_DEVICE_ID_JOYPAD_*`): bit `rawValue` of a port's state.
public enum RetroButton: Int, CaseIterable, Sendable {
    case b = 0, y, select, start, up, down, left, right, a, x, l, r, l2, r2, l3, r3

    public var bit: UInt16 { 1 << UInt16(rawValue) }
}
