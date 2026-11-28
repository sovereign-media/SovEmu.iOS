import Foundation

extension WireProtocol {
    static let typeStats: UInt8 = 0x04

    /// This client's view of the stream (`0x04`: type, version, then a JSON object), sent once a
    /// second from connecting (before any video, while the worker checks the connection, only
    /// the round trip and the path): the worker lowers the video bitrate for a client that is not
    /// keeping up (`fps`, `frames_dropped`, `decode_ms`) and logs it beside its own health lines
    /// (`client stats`). Every value is optional, as `ClientStats` in SovEmu.Protocol; times in
    /// ms, rates in kbit/s.
    public struct Stats: Equatable, Sendable {
        /// The client and its version (`ios 1.0 (iPhone, iOS 18.1)`).
        public var client: String?
        /// Button to pixel, estimated from the parts below.
        public var estimateMs: Double?
        /// Button to frame, measured (`FrameLatency`).
        public var inputToFrameMs: Int64?
        /// The input round trip (send, the worker applies it on a frame, its ack), median and p95.
        public var inputRttP50Ms: Int64?
        public var inputRttP95Ms: Int64?
        public var netRttMs: Double?
        public var jitterMs: Double?
        public var decodeMs: Double?
        public var width: Int?
        public var height: Int?
        /// Frames decoded per second.
        public var fps: Double?
        public var kbps: Double?
        /// Video and audio packets lost, since the stream began.
        public var packetsLost: Int?
        /// Video frames dropped, since the stream began.
        public var framesDropped: Int?
        /// The video decoder (`decoderImplementation`).
        public var decoder: String?
        /// How this client reaches the worker (`LinkLabels.clientPath`): `direct`, or through the
        /// relay over `relay-udp`, `relay-tcp` or `relay-tls`.
        public var path: String?

        public init(client: String? = nil, estimateMs: Double? = nil, inputToFrameMs: Int64? = nil,
                    inputRttP50Ms: Int64? = nil, inputRttP95Ms: Int64? = nil, netRttMs: Double? = nil,
                    jitterMs: Double? = nil, decodeMs: Double? = nil,
                    width: Int? = nil, height: Int? = nil, fps: Double? = nil, kbps: Double? = nil,
                    packetsLost: Int? = nil, framesDropped: Int? = nil, decoder: String? = nil, path: String? = nil) {
            (self.client, self.estimateMs, self.inputToFrameMs) = (client, estimateMs, inputToFrameMs)
            (self.inputRttP50Ms, self.inputRttP95Ms) = (inputRttP50Ms, inputRttP95Ms)
            (self.netRttMs, self.jitterMs, self.decodeMs) = (netRttMs, jitterMs, decodeMs)
            (self.width, self.height, self.fps, self.kbps) = (width, height, fps, kbps)
            (self.packetsLost, self.framesDropped, self.decoder) = (packetsLost, framesDropped, decoder)
            self.path = path
        }
    }

    /// The known values in `ClientStats`'s order; nils and non-finite numbers are left out, and
    /// numbers rounded to one decimal, as the other clients write them.
    public static func encodeStats(_ stats: Stats) -> Data {
        func number(_ x: Double?) -> String? {
            guard let x, x.isFinite else { return nil }
            let rounded = (x * 10).rounded() / 10
            return rounded == rounded.rounded() ? String(Int64(rounded)) : String(rounded)
        }
        func integer(_ x: Int?) -> String? { x.map(String.init) }
        func long(_ x: Int64?) -> String? { x.map(String.init) }
        func string(_ x: String?) -> String? {
            guard let x, let json = try? JSONEncoder().encode(x) else { return nil }
            return String(decoding: json, as: UTF8.self)
        }
        let fields: [(String, String?)] = [
            ("client", string(stats.client)),
            ("estimate_ms", number(stats.estimateMs)),
            ("input_to_frame_ms", long(stats.inputToFrameMs)),
            ("input_rtt_p50_ms", long(stats.inputRttP50Ms)),
            ("input_rtt_p95_ms", long(stats.inputRttP95Ms)),
            ("net_rtt_ms", number(stats.netRttMs)),
            ("jitter_ms", number(stats.jitterMs)),
            ("decode_ms", number(stats.decodeMs)),
            ("width", integer(stats.width)),
            ("height", integer(stats.height)),
            ("fps", number(stats.fps)),
            ("kbps", number(stats.kbps)),
            ("packets_lost", integer(stats.packetsLost)),
            ("frames_dropped", integer(stats.framesDropped)),
            ("decoder", string(stats.decoder)),
            ("path", string(stats.path)),
        ]
        let body = fields.compactMap { key, value in value.map { "\"\(key)\":\($0)" } }.joined(separator: ",")
        return Data([typeStats, inputVersion]) + Data("{\(body)}".utf8)
    }
}

extension WireProtocol {
    /// A change in the stream's quality, as the player is told of it: one line, and the glyph
    /// before it (`wifi-alert` and `wifi-up`, Sovereign's own, or `gauge` for a device that
    /// fell behind).
    public struct QualityNotice: Equatable, Sendable {
        public var line: String
        public var icon: String

        public init(line: String, icon: String) {
            (self.line, self.icon) = (line, icon)
        }
    }

    /// The notice for a change in the stream's quality between two pipeline messages, worded
    /// and marked as Sovereign's step-down and step-up notices and the other clients': the
    /// bitrate the worker tells the player of moved (it only does in steps worth telling). Nil
    /// when it has not, or when either side does not know it (the first message, an older
    /// server).
    public static func qualityNotice(before: Pipeline?, now: Pipeline) -> QualityNotice? {
        let (was, current) = (before?.video.kbps ?? 0, now.video.kbps)
        guard was != 0, current != 0, was != current else { return nil }
        if current < was {
            return now.video.limitedBy == "client"
                ? QualityNotice(line: "This device is falling behind. Playing at a lower quality.", icon: "gauge")
                : QualityNotice(line: "Slow connection. Playing at a lower quality.", icon: "wifi-alert")
        }
        // Back up from a fall that was the device's: the connection had nothing to do with it.
        return before?.video.limitedBy == "client"
            ? QualityNotice(line: "Playing at a higher quality.", icon: "gauge")
            : QualityNotice(line: "Connection improved. Playing at a higher quality.", icon: "wifi-up")
    }
}

/// One reading of a peer connection's stats (WebRTC's `statistics`): the inbound video's
/// counters, cumulative as WebRTC reports them, and the selected candidate pair (its round trip
/// and both ends).
public struct StatsReading: Equatable, Sendable {
    /// Seconds, on any clock that only moves forward.
    public var at: Double
    public var bytesReceived: Double
    /// Seconds, summed over every emitted frame.
    public var jitterBufferDelay: Double
    public var jitterBufferEmittedCount: Double
    /// Seconds, summed over every decoded frame.
    public var totalDecodeTime: Double
    public var framesDecoded: Double
    public var framesPerSecond: Double?
    public var width: Int?
    public var height: Int?
    /// Video and audio together.
    public var packetsLost: Int
    public var framesDropped: Int?
    public var networkRttMs: Double?
    public var decoder: String?
    /// There is an inbound video stream to read: false before the first frame, while the worker
    /// checks the connection and sends none.
    public var hasVideo: Bool
    /// The selected candidate pair's two ends; nil before ICE has chosen one.
    public var local: IceCandidateStats?
    public var remote: IceCandidateStats?

    public init(at: Double, bytesReceived: Double = 0, jitterBufferDelay: Double = 0, jitterBufferEmittedCount: Double = 0,
                totalDecodeTime: Double = 0, framesDecoded: Double = 0, framesPerSecond: Double? = nil,
                width: Int? = nil, height: Int? = nil, packetsLost: Int = 0, framesDropped: Int? = nil,
                networkRttMs: Double? = nil, decoder: String? = nil, hasVideo: Bool = true,
                local: IceCandidateStats? = nil, remote: IceCandidateStats? = nil) {
        (self.at, self.bytesReceived) = (at, bytesReceived)
        (self.jitterBufferDelay, self.jitterBufferEmittedCount) = (jitterBufferDelay, jitterBufferEmittedCount)
        (self.totalDecodeTime, self.framesDecoded, self.framesPerSecond) = (totalDecodeTime, framesDecoded, framesPerSecond)
        (self.width, self.height, self.packetsLost, self.framesDropped) = (width, height, packetsLost, framesDropped)
        (self.networkRttMs, self.decoder) = (networkRttMs, decoder)
        (self.hasVideo, self.local, self.remote) = (hasVideo, local, remote)
    }

    /// The packets lost of the inbound video and audio together, each at least 0 as the web's
    /// stats: WebRTC counts a duplicated packet as one fewer lost, so a stream with duplicates
    /// and no loss reports a negative count, which the worker would log as nonsense.
    public static func packetsLost(video: Double?, audio: Double?) -> Int {
        Int(max(0, video ?? 0)) + Int(max(0, audio ?? 0))
    }
}

/// Turns successive readings into the stats message: rates and per-frame averages come from the
/// change since the previous reading (so the first knows none of them), as the web client's
/// `StatsSampler` and SovEmu.Android's do.
public struct StatsSampler: Sendable {
    private var last: StatsReading?

    public init() {}

    /// `inputRtts`: the recent input round trips in ms, in any order; `inputToFrameMs`: the
    /// measured button→frame (`FrameLatency.medianMs`).
    public mutating func sample(_ now: StatsReading, client: String? = nil, inputRtts: [Int64] = [],
                                inputToFrameMs: Int64? = nil) -> WireProtocol.Stats {
        let prev = last
        last = now
        let path = LinkLabels.clientPath(now.local)
        // Before the first frame (the worker checking the connection): the round trip and the
        // path already go to the worker, which judges the link by them.
        guard now.hasVideo else { return WireProtocol.Stats(client: client, netRttMs: now.networkRttMs, path: path) }
        func perFrame(_ total: KeyPath<StatsReading, Double>, _ count: KeyPath<StatsReading, Double>) -> Double? {
            guard let prev else { return nil }
            let n = now[keyPath: count] - prev[keyPath: count]
            return n > 0 ? (now[keyPath: total] - prev[keyPath: total]) / n * 1000 : nil
        }
        let seconds = prev.map { now.at - $0.at }.flatMap { $0 > 0 ? $0 : nil }
        let sorted = inputRtts.sorted()
        let p50 = percentile(sorted, 50)
        let jitter = perFrame(\.jitterBufferDelay, \.jitterBufferEmittedCount)
        let decode = perFrame(\.totalDecodeTime, \.framesDecoded)
        // Button to pixel, roughly, as the other clients estimate it: the input round trip (the
        // input reaches the core and the frame comes back), plus half a frame of alignment, ~2 ms
        // encode, the jitter buffer, decode and half a display refresh at 60 Hz.
        let estimate = p50.map { Double($0) + 8 + 2 + (jitter ?? 0) + (decode ?? 0) + 8 }
        return WireProtocol.Stats(
            client: client,
            estimateMs: estimate,
            inputToFrameMs: inputToFrameMs,
            inputRttP50Ms: p50,
            inputRttP95Ms: percentile(sorted, 95),
            netRttMs: now.networkRttMs,
            jitterMs: jitter,
            decodeMs: decode,
            width: now.width,
            height: now.height,
            fps: now.framesPerSecond,
            kbps: seconds.map { (now.bytesReceived - (prev?.bytesReceived ?? 0)) * 8 / 1000 / $0 },
            packetsLost: max(0, now.packetsLost),
            framesDropped: now.framesDropped,
            decoder: now.decoder,
            path: path)
    }
}

extension WireProtocol.Stats {
    /// The stats overlay's rows, label and value, in the order the other clients show them.
    public func rows() -> [(label: String, value: String)] {
        func ms(_ x: Double?, _ digits: Int) -> String {
            guard let x, x.isFinite else { return "–" }
            return String(format: "%.\(digits)f ms", locale: Locale(identifier: "en_US_POSIX"), x)
        }
        let rtt = inputRttP50Ms.map { "\($0) ms · p95 \(inputRttP95Ms.map(String.init) ?? "–")" } ?? "–"
        let video = "\(width.map(String.init) ?? "?")×\(height.map(String.init) ?? "?") @ \(fps.map { String(Int($0.rounded())) } ?? "–") fps"
        return [
            ("Estimated button→pixel", ms(estimateMs, 0)),
            ("Measured button→frame", ms(inputToFrameMs.map(Double.init), 0)),
            ("Input round trip", rtt),
            ("Network RTT", ms(netRttMs, 1)),
            ("Jitter buffer", ms(jitterMs, 1)),
            ("Decode", ms(decodeMs, 1)),
            ("Video", video),
            ("Bitrate", kbps.map { "\(Int($0.rounded())) kbps" } ?? "–"),
            ("Packets lost", String(packetsLost ?? 0)),
        ]
    }
}

extension WireProtocol {
    /// Everything the stats overlay shows for one sample, as the web's `StatsSampler`: the
    /// stats' rows and the worker's `pipeline` once there is video, then the Network rows from
    /// the selected pair, the check of the connection (`link`) and the pipeline's estimate.
    /// Before the first frame only the Network rows: the rest would be dashes.
    public static func overlayRows(_ stats: Stats, reading: StatsReading, pipeline: Pipeline?,
                                   link: Link?) -> [(label: String, value: String)] {
        let network = networkRows(local: reading.local, remote: reading.remote, link: link,
                                  estimateKbps: pipeline?.video.estimateKbps ?? 0)
        guard reading.hasVideo else { return network }
        return stats.rows() + pipelineRows(pipeline, decoder: stats.decoder) + network
    }

    /// The overlay's rows on how the stream is made, after the stats': the worker's `pipeline`
    /// (none from a server that predates it, so no rows) and this app's `decoder`. The labels
    /// and formats are the other clients'.
    public static func pipelineRows(_ pipeline: Pipeline?, decoder: String?) -> [(label: String, value: String)] {
        guard let pipeline else { return [] }
        let video = pipeline.video
        var rows: [(label: String, value: String)] = [
            ("Stream", "\(codecName(video.codec)) · \(encoderName(video.encoder)) (\(video.hardware ? "GPU" : "CPU"))"),
        ]
        if !video.fallbacks.isEmpty {
            rows.append(("Fell back from", video.fallbacks.map { "\(encoderName($0.encoder)): \($0.reason)" }.joined(separator: "; ")))
        }
        let rendering = pipeline.renderer.map { pipeline.rendererSoftware ? "Software · \($0)" : "GPU · \($0)" } ?? "CPU"
        rows.append(("Rendering", rendering))
        // Grouped as the other clients write it ("32,040"), whatever the device's language.
        let grouping = NumberFormatter()
        grouping.locale = Locale(identifier: "en_US")
        grouping.numberStyle = .decimal
        let hz = grouping.string(from: NSNumber(value: Int(pipeline.audio.sourceHz.rounded()))) ?? "\(Int(pipeline.audio.sourceHz))"
        rows.append(("Audio", "\(codecName(pipeline.audio.codec)) \(pipeline.audio.kbps) kbps · from \(hz) Hz"))
        rows.append(("Run-ahead", pipeline.runAhead == 0 ? "Off" : pipeline.runAhead == 1 ? "1 frame" : "\(pipeline.runAhead) frames"))
        if let decoder { rows.append(("Decoder", decoder)) }
        return rows
    }

    /// A codec's display name; one this app does not know shows as the worker names it.
    static func codecName(_ codec: String) -> String {
        ["h264": "H.264", "vp8": "VP8", "opus": "Opus"][codec] ?? codec
    }

    /// An encoder's display name; one this app does not know shows as the worker names it.
    static func encoderName(_ encoder: String) -> String {
        ["vaapi": "VA-API", "nvenc": "NVENC"][encoder] ?? encoder
    }
}
