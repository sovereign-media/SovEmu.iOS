import Foundation

extension WireProtocol {
    static let typeStats: UInt8 = 0x04

    /// This client's view of the stream (`0x04`: type, version, then a JSON object), sent once a
    /// second while playing: the worker lowers the video bitrate for a client that is not
    /// keeping up (`fps`, `frames_dropped`, `decode_ms`) and logs it beside its own health lines
    /// (`client stats`). Every value is optional, as `ClientStats` in SovEmu.Protocol; times in
    /// ms, rates in kbit/s.
    public struct Stats: Equatable, Sendable {
        /// The client and its version (`ios 1.0 (iPhone, iOS 18.1)`).
        public var client: String?
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

        public init(client: String? = nil, netRttMs: Double? = nil, jitterMs: Double? = nil, decodeMs: Double? = nil,
                    width: Int? = nil, height: Int? = nil, fps: Double? = nil, kbps: Double? = nil,
                    packetsLost: Int? = nil, framesDropped: Int? = nil, decoder: String? = nil) {
            (self.client, self.netRttMs, self.jitterMs, self.decodeMs) = (client, netRttMs, jitterMs, decodeMs)
            (self.width, self.height, self.fps, self.kbps) = (width, height, fps, kbps)
            (self.packetsLost, self.framesDropped, self.decoder) = (packetsLost, framesDropped, decoder)
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
        func string(_ x: String?) -> String? {
            guard let x, let json = try? JSONEncoder().encode(x) else { return nil }
            return String(decoding: json, as: UTF8.self)
        }
        let fields: [(String, String?)] = [
            ("client", string(stats.client)),
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
/// counters, cumulative as WebRTC reports them, and the selected candidate pair's round trip.
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

    public init(at: Double, bytesReceived: Double = 0, jitterBufferDelay: Double = 0, jitterBufferEmittedCount: Double = 0,
                totalDecodeTime: Double = 0, framesDecoded: Double = 0, framesPerSecond: Double? = nil,
                width: Int? = nil, height: Int? = nil, packetsLost: Int = 0, framesDropped: Int? = nil,
                networkRttMs: Double? = nil, decoder: String? = nil) {
        (self.at, self.bytesReceived) = (at, bytesReceived)
        (self.jitterBufferDelay, self.jitterBufferEmittedCount) = (jitterBufferDelay, jitterBufferEmittedCount)
        (self.totalDecodeTime, self.framesDecoded, self.framesPerSecond) = (totalDecodeTime, framesDecoded, framesPerSecond)
        (self.width, self.height, self.packetsLost, self.framesDropped) = (width, height, packetsLost, framesDropped)
        (self.networkRttMs, self.decoder) = (networkRttMs, decoder)
    }
}

/// Turns successive readings into the stats message: rates and per-frame averages come from the
/// change since the previous reading (so the first knows none of them), as the web client's
/// `StatsSampler` and SovEmu.Android's do.
public struct StatsSampler: Sendable {
    private var last: StatsReading?

    public init() {}

    public mutating func sample(_ now: StatsReading, client: String? = nil) -> WireProtocol.Stats {
        let prev = last
        last = now
        func perFrame(_ total: KeyPath<StatsReading, Double>, _ count: KeyPath<StatsReading, Double>) -> Double? {
            guard let prev else { return nil }
            let n = now[keyPath: count] - prev[keyPath: count]
            return n > 0 ? (now[keyPath: total] - prev[keyPath: total]) / n * 1000 : nil
        }
        let seconds = prev.map { now.at - $0.at }.flatMap { $0 > 0 ? $0 : nil }
        return WireProtocol.Stats(
            client: client,
            netRttMs: now.networkRttMs,
            jitterMs: perFrame(\.jitterBufferDelay, \.jitterBufferEmittedCount),
            decodeMs: perFrame(\.totalDecodeTime, \.framesDecoded),
            width: now.width,
            height: now.height,
            fps: now.framesPerSecond,
            kbps: seconds.map { (now.bytesReceived - (prev?.bytesReceived ?? 0)) * 8 / 1000 / $0 },
            packetsLost: now.packetsLost,
            framesDropped: now.framesDropped,
            decoder: now.decoder)
    }
}
