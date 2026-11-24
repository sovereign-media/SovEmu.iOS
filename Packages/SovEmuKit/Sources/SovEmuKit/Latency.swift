import Foundation

/// Button to frame, measured, as SovEmu.Android's `FrameLatency`: from sending an input to the
/// renderer getting the frame that shows it. The worker writes each ack just before the RTP
/// video of the frame that consumed the input, so that frame is the first to *enter the
/// decoder* after the ack. It is not always the first to leave it: a decoder slower than a frame
/// still holds older frames, and those come out first. So an ack is bound to the next frame in
/// (`frameEntered`) and recorded when that frame, or a later one if it was dropped, comes out
/// (`frameDelivered`).
///
/// Frames are matched across the decoder by an identity that survives it, found by watching the
/// first frames out (`match`): the render time, else the capture time, else the count of frames
/// in and out. When nothing reports frames going in (on iOS WebRTC decodes in native code, out of
/// sight), the first frame out after the ack counts: exact for a decoder faster than a frame.
///
/// The oldest pending ack is kept: a newer one's frame comes later still. One that no frame has
/// shown within `pendingTimeoutMs` is dropped. Times are the app's 32-bit millisecond clock, the
/// one `client_time_ms` carries. Acks arrive on WebRTC's data channel thread and frames on its
/// render thread: a lock guards the little state, held for a few comparisons at a time.
public final class FrameLatency: @unchecked Sendable {
    /// How frames are told apart across the decoder.
    public enum Match: Sendable { case unknown, renderTime, captureTime, count }

    private struct Entered { let renderTimeMs: Int64, captureTimeNs: Int64, index: Int64 }
    private struct Pending { let sentMs: Int64, arrivedMs: Int64, frame: Entered? }

    public static let defaultCapacity = 60
    /// Longer than any real button-to-frame time; anything above is a clock wrap.
    public static let maxPlausibleMs: Int64 = 10_000
    /// A pending ack no frame has shown by now is dropped.
    public static let pendingTimeoutMs: Int64 = 2_000
    /// Frames out, without a timestamp match, before matching falls back to counting.
    public static let learnFrames: Int64 = 30
    /// No frame in for this long: frames are not being watched going in (any more).
    public static let entrySilenceMs: Int64 = 500

    private static let recent = 16
    private static let mask: Int64 = 0xffff_ffff
    private static let nsPerMs: Int64 = 1_000_000

    private let lock = NSLock()
    private let capacity: Int
    private var pending: Pending?
    private var framesIn: Int64 = 0
    private var framesOut: Int64 = 0
    private var lastEnteredMs: Int64?
    private var recentRender: [Int64]
    private var recentCapture: [Int64]
    private var matchState = Match.unknown
    private var samples: [Int64]
    private var written = 0

    public init(capacity: Int = FrameLatency.defaultCapacity) {
        self.capacity = capacity
        samples = Array(repeating: 0, count: capacity)
        recentRender = Array(repeating: 0, count: Self.recent)
        recentCapture = Array(repeating: 0, count: Self.recent)
    }

    /// How frames are matched, once the first frames out have shown it.
    public var match: Match { lock.withLock { matchState } }

    /// An ack for the input sent at `clientTimeMs` arrived at `nowMs`.
    public func ackArrived(clientTimeMs: Int64, nowMs: Int64) {
        lock.withLock {
            if let current = pending, age(nowMs, current.arrivedMs) <= Self.pendingTimeoutMs { return }
            pending = Pending(sentMs: clientTimeMs & Self.mask, arrivedMs: nowMs & Self.mask, frame: nil)
        }
    }

    /// An encoded frame went into the decoder at `nowMs`, with its planned render time and
    /// capture time.
    public func frameEntered(renderTimeMs: Int64, captureTimeNs: Int64, nowMs: Int64) {
        lock.withLock {
            framesIn += 1
            let index = framesIn
            lastEnteredMs = nowMs & Self.mask
            if matchState == .unknown {
                let slot = Int(index % Int64(Self.recent))
                recentRender[slot] = renderTimeMs
                recentCapture[slot] = captureTimeNs
            }
            guard let current = pending, current.frame == nil else { return }
            pending = Pending(sentMs: current.sentMs, arrivedMs: current.arrivedMs,
                              frame: Entered(renderTimeMs: renderTimeMs, captureTimeNs: captureTimeNs, index: index))
        }
    }

    /// A decoded frame with WebRTC's `timestampNs` was handed to the renderer at `nowMs`.
    public func frameDelivered(timestampNs: Int64, nowMs: Int64) {
        lock.withLock {
            framesOut += 1
            let index = framesOut
            if matchState == .unknown { learn(timestampNs, index) }
            guard let current = pending else { return }
            if age(nowMs, current.arrivedMs) > Self.pendingTimeoutMs {
                pending = nil
                return
            }
            let shows: Bool
            if let frame = current.frame {
                switch matchState {
                case .renderTime: shows = timestampNs / Self.nsPerMs >= frame.renderTimeMs
                case .captureTime: shows = timestampNs / Self.nsPerMs >= frame.captureTimeNs / Self.nsPerMs
                case .count, .unknown: shows = index >= frame.index
                }
            } else {
                // Nothing is watching frames go in (or has, lately): the first frame out counts.
                shows = lastEnteredMs.map { age(nowMs, $0) > Self.entrySilenceMs } ?? true
            }
            guard shows else { return }
            pending = nil
            let latency = age(nowMs, current.sentMs)
            guard latency <= Self.maxPlausibleMs else { return }
            samples[written % capacity] = latency
            written += 1
        }
    }

    /// Which identity the frames out carry: a timestamp equal to a recent frame's render time or
    /// capture time, else (after `learnFrames` frames out without one) their count.
    private func learn(_ timestampNs: Int64, _ index: Int64) {
        guard framesIn > 0 else { return }
        let ms = timestampNs / Self.nsPerMs
        if ms != 0 {
            for i in 0..<Self.recent {
                if recentRender[i] == ms {
                    matchState = .renderTime
                    return
                }
                if recentCapture[i] / Self.nsPerMs == ms {
                    matchState = .captureTime
                    return
                }
            }
        }
        if index >= Self.learnFrames { matchState = .count }
    }

    /// Samples kept, up to the capacity.
    public var count: Int { lock.withLock { min(written, capacity) } }

    /// The median of the last samples (nearest rank), or nil before any.
    public func medianMs() -> Int64? {
        let held = lock.withLock { Array(samples.prefix(min(written, capacity))) }
        return percentile(held.sorted(), 50)
    }

    private func age(_ nowMs: Int64, _ thenMs: Int64) -> Int64 { (nowMs - thenMs) & Self.mask }
}

/// The stats overlay's latency graph: the last `capacity` samples (one a second) of the
/// measured button→frame and the estimated button→pixel, oldest first, and the graph's y scale.
/// An unknown value is NaN (a gap in its line).
public struct LatencyHistory: Sendable {
    public static let defaultCapacity = 60
    public static let scaleStepMs = 25.0
    public static let minScaleMs = 50.0

    public let capacity: Int
    private var measuredValues: [Double]
    private var estimatedValues: [Double]
    private var next = 0
    /// Samples held, up to `capacity`.
    public private(set) var size = 0

    public init(capacity: Int = LatencyHistory.defaultCapacity) {
        self.capacity = capacity
        measuredValues = Array(repeating: .nan, count: capacity)
        estimatedValues = Array(repeating: .nan, count: capacity)
    }

    public mutating func add(measured: Double?, estimated: Double?) {
        measuredValues[next] = measured ?? .nan
        estimatedValues[next] = estimated ?? .nan
        next = (next + 1) % capacity
        size = min(size + 1, capacity)
    }

    /// Forgets every sample (the overlay was turned off, or a new stream began).
    public mutating func clear() {
        next = 0
        size = 0
    }

    /// The `i`th held sample, 0 the oldest; NaN when unknown.
    public func measured(_ i: Int) -> Double { measuredValues[slot(i)] }
    public func estimated(_ i: Int) -> Double { estimatedValues[slot(i)] }

    /// The newest measured value, or nil when the newest sample has none.
    public var latestMeasured: Double? {
        guard size > 0 else { return nil }
        let v = measured(size - 1)
        return v.isNaN ? nil : v
    }

    /// The top of the y axis in ms: the highest value held, rounded up to a multiple of
    /// `scaleStepMs`, and never below `minScaleMs`.
    public func scaleMaxMs() -> Double {
        var highest = 0.0
        for i in 0..<size {
            for v in [measured(i), estimated(i)] where !v.isNaN && v > highest { highest = v }
        }
        return max(Self.minScaleMs, (highest / Self.scaleStepMs).rounded(.up) * Self.scaleStepMs)
    }

    private func slot(_ i: Int) -> Int {
        precondition((0..<size).contains(i), "sample \(i) of \(size)")
        return (next - size + i + capacity) % capacity
    }
}

/// Nearest-rank percentile of an ascending list; nil when it is empty.
public func percentile(_ sorted: [Int64], _ p: Int) -> Int64? {
    guard !sorted.isEmpty else { return nil }
    let rank = min(sorted.count, max(1, Int((Double(p) / 100 * Double(sorted.count)).rounded(.up))))
    return sorted[rank - 1]
}
