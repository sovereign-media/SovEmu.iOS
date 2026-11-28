import Synchronization

// The input round trips the stats report, as SovEmu.Android's `RecentRtts` (the web keeps the
// same 60 in `session.ts`'s `inputRtts`): every client sends the worker a median and p95 over
// the same window, so their numbers compare.

/// The last input round trips in ms (send, the worker applies the input on a frame, its ack):
/// a ring of `capacity`. Acks arrive on WebRTC's data channel thread and the stats read it on
/// the main thread, so it sits behind a Mutex.
public final class RecentRtts: Sendable {
    /// About two seconds of acks while a button is held, and a minute's at the heartbeat.
    public static let defaultCapacity = 60

    private struct Ring {
        var values: [Int64]
        var next = 0
        var size = 0
    }

    private let capacity: Int
    private let ring: Mutex<Ring>

    public init(capacity: Int = RecentRtts.defaultCapacity) {
        precondition(capacity > 0, "a ring holds at least one round trip")
        self.capacity = capacity
        ring = Mutex(Ring(values: Array(repeating: 0, count: capacity)))
    }

    public func add(_ ms: Int64) {
        ring.withLock { r in
            r.values[r.next] = ms
            r.next = (r.next + 1) % capacity
            r.size = min(r.size + 1, capacity)
        }
    }

    /// The round trips held, oldest first.
    public func values() -> [Int64] {
        ring.withLock { r in (0..<r.size).map { r.values[(r.next - r.size + $0 + capacity) % capacity] } }
    }
}
