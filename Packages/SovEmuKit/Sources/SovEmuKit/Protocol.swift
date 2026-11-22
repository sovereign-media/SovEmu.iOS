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
    static let typePipeline: UInt8 = 0x82
    /// The longest pipeline message, header included.
    public static let maxPipelineLength = 4096

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

    /// How the worker makes the stream (`0x82`: type, version, then a JSON object), sent when
    /// the channel opens, on every change and every 2 s. Every key may be missing (an empty or
    /// zero default) and unknown keys are ignored, as `Pipeline` in SovEmu.Protocol.
    public struct Pipeline: Equatable, Sendable, Decodable {
        /// The OpenGL renderer a 3D core draws with; nil for a core that draws on the CPU.
        public var renderer: String?
        /// The renderer is the software one (llvmpipe), not a GPU.
        public var rendererSoftware: Bool
        public var video: Video
        public var audio: Audio
        /// Frames the picture runs ahead of the game (0: off).
        public var runAhead: Int

        public init(renderer: String? = nil, rendererSoftware: Bool = false, video: Video = Video(),
                    audio: Audio = Audio(), runAhead: Int = 0) {
            (self.renderer, self.rendererSoftware, self.video, self.audio, self.runAhead) =
                (renderer, rendererSoftware, video, audio, runAhead)
        }

        enum CodingKeys: String, CodingKey {
            case renderer, video, audio
            case rendererSoftware = "renderer_software", runAhead = "run_ahead"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            renderer = try c.decodeIfPresent(String.self, forKey: .renderer)
            rendererSoftware = try c.decodeIfPresent(Bool.self, forKey: .rendererSoftware) ?? false
            video = try c.decodeIfPresent(Video.self, forKey: .video) ?? Video()
            audio = try c.decodeIfPresent(Audio.self, forKey: .audio) ?? Audio()
            runAhead = try c.decodeIfPresent(Int.self, forKey: .runAhead) ?? 0
        }

        public struct Video: Equatable, Sendable, Decodable {
            /// `h264` or `vp8`.
            public var codec: String
            /// `vaapi`, `nvenc`, `x264` or `libvpx`.
            public var encoder: String
            /// The encoder runs on a GPU.
            public var hardware: Bool
            /// Encoders tried before this one, in order, and why each was given up.
            public var fallbacks: [Fallback]
            /// The encoded picture, before the client scales it.
            public var width: Int
            public var height: Int
            public var fps: Double
            /// The video bitrate as last told to the player, kbit/s: it moves in steps worth a
            /// notice, so a change from the one before is shown (`qualityNotice`). 0: unknown
            /// (an older server).
            public var kbps: Int
            /// What held it down when it last fell: `connection`, `client`, or empty.
            public var limitedBy: String

            public init(codec: String = "", encoder: String = "", hardware: Bool = false, fallbacks: [Fallback] = [],
                        width: Int = 0, height: Int = 0, fps: Double = 0, kbps: Int = 0, limitedBy: String = "") {
                (self.codec, self.encoder, self.hardware, self.fallbacks) = (codec, encoder, hardware, fallbacks)
                (self.width, self.height, self.fps) = (width, height, fps)
                (self.kbps, self.limitedBy) = (kbps, limitedBy)
            }

            enum CodingKeys: String, CodingKey {
                case codec, encoder, hardware, fallbacks, width, height, fps, kbps
                case limitedBy = "limited_by"
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                codec = try c.decodeIfPresent(String.self, forKey: .codec) ?? ""
                encoder = try c.decodeIfPresent(String.self, forKey: .encoder) ?? ""
                hardware = try c.decodeIfPresent(Bool.self, forKey: .hardware) ?? false
                fallbacks = try c.decodeIfPresent([Fallback].self, forKey: .fallbacks) ?? []
                width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
                height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
                fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? 0
                kbps = try c.decodeIfPresent(Int.self, forKey: .kbps) ?? 0
                limitedBy = try c.decodeIfPresent(String.self, forKey: .limitedBy) ?? ""
            }
        }

        /// An encoder given up, and why.
        public struct Fallback: Equatable, Sendable, Decodable {
            public var encoder: String
            public var reason: String

            public init(encoder: String = "", reason: String = "") {
                (self.encoder, self.reason) = (encoder, reason)
            }

            enum CodingKeys: String, CodingKey { case encoder, reason }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                encoder = try c.decodeIfPresent(String.self, forKey: .encoder) ?? ""
                reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
            }
        }

        public struct Audio: Equatable, Sendable, Decodable {
            /// `opus`.
            public var codec: String
            /// The core's own sample rate, resampled to 48 kHz.
            public var sourceHz: Double
            public var kbps: Int

            public init(codec: String = "", sourceHz: Double = 0, kbps: Int = 0) {
                (self.codec, self.sourceHz, self.kbps) = (codec, sourceHz, kbps)
            }

            enum CodingKeys: String, CodingKey { case codec, kbps, sourceHz = "source_hz" }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                codec = try c.decodeIfPresent(String.self, forKey: .codec) ?? ""
                sourceHz = try c.decodeIfPresent(Double.self, forKey: .sourceHz) ?? 0
                kbps = try c.decodeIfPresent(Int.self, forKey: .kbps) ?? 0
            }
        }
    }

    /// Decodes a pipeline message, or returns nil for anything else (another type or version,
    /// too long, or a body that is not a JSON object of the expected shape).
    public static func decodePipeline(_ data: Data) -> Pipeline? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes.count <= maxPipelineLength, bytes[0] == typePipeline, bytes[1] == inputVersion
        else { return nil }
        return try? JSONDecoder().decode(Pipeline.self, from: Data(bytes[2...]))
    }
}

/// RetroPad buttons (libretro `RETRO_DEVICE_ID_JOYPAD_*`): bit `rawValue` of a port's state.
public enum RetroButton: Int, CaseIterable, Sendable {
    case b = 0, y, select, start, up, down, left, right, a, x, l, r, l2, r2, l3, r3

    public var bit: UInt16 { 1 << UInt16(rawValue) }
}
