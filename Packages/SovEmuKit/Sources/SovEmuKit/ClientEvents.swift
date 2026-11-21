import Foundation

/// What went wrong on a client, as the server's `ClientEventKind` names it.
public enum ClientEventKind: String, Sendable {
    case connectionFailed = "CONNECTION_FAILED"
    case connectionLost = "CONNECTION_LOST"
    case streamStalled = "STREAM_STALLED"
    case controllerUnknown = "CONTROLLER_UNKNOWN"
    case screenError = "SCREEN_ERROR"
    case other = "OTHER"
}

/// One thing that went wrong on this device, for the server's log (`reportClientEvents`).
public struct ClientEvent: Sendable, Equatable {
    public let kind: ClientEventKind
    public let message: String
    public let sessionId: String?
    /// Seconds since the Unix epoch.
    public let at: Double
}

/// Gathers events for the server: each distinct one once (a fault repeating every frame is sent
/// once), in batches no larger than the server takes. When to send is the caller's.
public final class ClientEventQueue: @unchecked Sendable {
    /// The server takes at most this many a call.
    public static let maxBatch = 20
    public static let maxMessage = 500
    private static let maxDistinct = 200

    private let lock = NSLock()
    private var queue: [ClientEvent] = []
    private var seen: Set<String> = []
    private let now: @Sendable () -> Double

    public init(now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.now = now
    }

    /// Queues an event; false if it was sent before (or too many distinct ones have been).
    @discardableResult
    public func add(_ kind: ClientEventKind, _ message: String, sessionId: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(kind.rawValue)|\(message)|\(sessionId ?? "")"
        guard seen.count < Self.maxDistinct, seen.insert(key).inserted else { return false }
        queue.append(ClientEvent(kind: kind, message: String(message.prefix(Self.maxMessage)), sessionId: sessionId, at: now()))
        return true
    }

    /// What has gathered, in batches of at most `maxBatch`; the queue is then empty.
    public func take() -> [[ClientEvent]] {
        lock.lock()
        defer { lock.unlock() }
        let all = queue
        queue.removeAll()
        return stride(from: 0, to: all.count, by: Self.maxBatch).map { Array(all[$0..<min($0 + Self.maxBatch, all.count)]) }
    }
}
