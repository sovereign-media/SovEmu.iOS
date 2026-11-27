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
    static let typeLink: UInt8 = 0x83
    /// The longest pipeline message, header included.
    public static let maxPipelineLength = 4096
    /// The longest link message, header included.
    public static let maxLinkLength = 1024

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
        /// The check of the connection before the stream started, once done: what the stats
        /// overlay shows as measured at start. Nil while it runs, without one, or from an older
        /// server.
        public var link: Link?

        public init(renderer: String? = nil, rendererSoftware: Bool = false, video: Video = Video(),
                    audio: Audio = Audio(), runAhead: Int = 0, link: Link? = nil) {
            (self.renderer, self.rendererSoftware, self.video, self.audio, self.runAhead) =
                (renderer, rendererSoftware, video, audio, runAhead)
            self.link = link
        }

        enum CodingKeys: String, CodingKey {
            case renderer, video, audio, link
            case rendererSoftware = "renderer_software", runAhead = "run_ahead"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            renderer = try c.decodeIfPresent(String.self, forKey: .renderer)
            rendererSoftware = try c.decodeIfPresent(Bool.self, forKey: .rendererSoftware) ?? false
            video = try c.decodeIfPresent(Video.self, forKey: .video) ?? Video()
            audio = try c.decodeIfPresent(Audio.self, forKey: .audio) ?? Audio()
            runAhead = try c.decodeIfPresent(Int.self, forKey: .runAhead) ?? 0
            link = try c.decodeIfPresent(Link.self, forKey: .link)
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
            /// The send-bandwidth estimate now, kbit/s, video and audio together (0: unknown, an
            /// older server): the overlay's "Estimate now".
            public var estimateKbps: Int

            public init(codec: String = "", encoder: String = "", hardware: Bool = false, fallbacks: [Fallback] = [],
                        width: Int = 0, height: Int = 0, fps: Double = 0, kbps: Int = 0, limitedBy: String = "",
                        estimateKbps: Int = 0) {
                (self.codec, self.encoder, self.hardware, self.fallbacks) = (codec, encoder, hardware, fallbacks)
                (self.width, self.height, self.fps) = (width, height, fps)
                (self.kbps, self.limitedBy, self.estimateKbps) = (kbps, limitedBy, estimateKbps)
            }

            enum CodingKeys: String, CodingKey {
                case codec, encoder, hardware, fallbacks, width, height, fps, kbps
                case limitedBy = "limited_by", estimateKbps = "estimate_kbps"
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
                estimateKbps = try c.decodeIfPresent(Int.self, forKey: .estimateKbps) ?? 0
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

    /// The check of the player's connection before a game starts (`0x83`: type, version, then a
    /// JSON object; `Link` in SovEmu.Protocol, #243). While `state` is `probing` the worker sends
    /// no video and the loading bar shows "Checking your connection" from `elapsedMs` of
    /// `budgetMs`; once `done` the stream starts at `startKbps`. Every key may be missing (an
    /// empty or zero default) and unknown keys are ignored.
    public struct Link: Equatable, Sendable, Decodable {
        /// `probing`, then `done`; empty for a state this app does not know.
        public var state: String
        /// How long the check has run, and may run, milliseconds.
        public var elapsedMs: Int
        public var budgetMs: Int
        /// `lan`, `direct`, `relay`, `relay-udp`, `relay-tcp` or `relay-tls`; empty while unknown.
        public var path: String
        /// The send-bandwidth estimate, kbit/s, video and audio together.
        public var estimateKbps: Int
        /// The video rate the stream starts at, kbit/s, once done.
        public var startKbps: Int
        /// The round trip the worker measures, milliseconds.
        public var rttMs: Double?
        /// `ceiling`, `steady`, `trouble`, `budget`, `unavailable` or `off`; empty while probing.
        public var stoppedBy: String

        public static let probing = "probing"
        public static let done = "done"

        public init(state: String = "", elapsedMs: Int = 0, budgetMs: Int = 0, path: String = "", estimateKbps: Int = 0,
                    startKbps: Int = 0, rttMs: Double? = nil, stoppedBy: String = "") {
            (self.state, self.elapsedMs, self.budgetMs, self.path) = (state, elapsedMs, budgetMs, path)
            (self.estimateKbps, self.startKbps, self.rttMs, self.stoppedBy) = (estimateKbps, startKbps, rttMs, stoppedBy)
        }

        enum CodingKeys: String, CodingKey {
            case state, path
            case elapsedMs = "elapsed_ms", budgetMs = "budget_ms", estimateKbps = "estimate_kbps"
            case startKbps = "start_kbps", rttMs = "rtt_ms", stoppedBy = "stopped_by"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
            self.state = state == Self.probing || state == Self.done ? state : ""
            elapsedMs = try c.decodeIfPresent(Int.self, forKey: .elapsedMs) ?? 0
            budgetMs = try c.decodeIfPresent(Int.self, forKey: .budgetMs) ?? 0
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
            estimateKbps = try c.decodeIfPresent(Int.self, forKey: .estimateKbps) ?? 0
            startKbps = try c.decodeIfPresent(Int.self, forKey: .startKbps) ?? 0
            rttMs = try c.decodeIfPresent(Double.self, forKey: .rttMs)
            stoppedBy = try c.decodeIfPresent(String.self, forKey: .stoppedBy) ?? ""
        }
    }

    /// Decodes a link message, or returns nil for anything else (another type or version, too
    /// long, or a body that is not a JSON object of the expected shape).
    public static func decodeLink(_ data: Data) -> Link? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes.count <= maxLinkLength, bytes[0] == typeLink, bytes[1] == inputVersion
        else { return nil }
        // A body that does not decode is not a link message: nil is the answer, not an error.
        return try? JSONDecoder().decode(Link.self, from: Data(bytes[2...]))
    }
}

/// RetroPad buttons (libretro `RETRO_DEVICE_ID_JOYPAD_*`): bit `rawValue` of a port's state.
public enum RetroButton: Int, CaseIterable, Sendable {
    case b = 0, y, select, start, up, down, left, right, a, x, l, r, l2, r2, l3, r3

    public var bit: UInt16 { 1 << UInt16(rawValue) }
}
