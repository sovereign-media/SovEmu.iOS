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
    static let typeAnalog: UInt8 = 0x03
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

    /// One port's analog controls: sticks −32768...32767 (x right, y down, libretro's
    /// convention), triggers 0...32767.
    public struct Analog: Equatable, Sendable {
        public var lx: Int, ly: Int, rx: Int, ry: Int, l2: Int, r2: Int

        public init(lx: Int = 0, ly: Int = 0, rx: Int = 0, ry: Int = 0, l2: Int = 0, r2: Int = 0) {
            (self.lx, self.ly, self.rx, self.ry, self.l2, self.r2) = (lx, ly, rx, ry, l2, r2)
        }

        public static let centred = Analog()

        /// A stick axis (−1...1) in libretro's range, with the dead zone taken out.
        public static func stick(_ v: Float) -> Int {
            let deadzone: Float = 0.15
            let m = abs(v)
            guard m >= deadzone else { return 0 }
            let scaled = min(1, (m - deadzone) / (1 - deadzone))
            return Int((v < 0 ? -scaled : scaled) * 32767)
        }

        public static func trigger(_ v: Float) -> Int { Int(min(1, max(0, v)) * 32767) }
    }

    /// Sticks and triggers (`0x03`): sent alongside button packets, with their own sequence.
    public static func encodeAnalog(seq: UInt32, ports: [Analog]) -> Data {
        let ports = ports.prefix(maxPorts)
        var out = Data([typeAnalog, inputVersion])
        out.append(contentsOf: withUnsafeBytes(of: seq.littleEndian, Array.init))
        out.append(UInt8(ports.count))
        for a in ports {
            for v in [a.lx, a.ly, a.rx, a.ry, a.l2, a.r2] {
                let clamped = Int16(max(-32768, min(32767, v)))
                out.append(contentsOf: withUnsafeBytes(of: clamped.littleEndian, Array.init))
            }
        }
        return out
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
