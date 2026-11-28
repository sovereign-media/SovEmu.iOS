import Foundation

// Reconnecting (SovEmu#302), as SovEmu.Web's launch.ts and SovEmu.Android's Reconnect.kt (same
// constants and cases): a connection that fails, stays disconnected past `disconnectedGraceMs`,
// or never connects within `connectTimeoutMs` is closed and offered again to the same session,
// which takes the new client in place of the old. After `attempts` reconnects the start has
// failed (`describeConnectionFailed`). Driven by the connection's states and the app's ticks,
// with the time passed in, so its tests need no clock.

public enum Reconnect {
    public static let attempts = 3
    public static let disconnectedGraceMs: Int64 = 5_000
    public static let connectTimeoutMs: Int64 = 15_000
}

/// A connection's state, as WebRTC's `RTCPeerConnectionState` names it.
public enum PeerState: Sendable {
    case new, connecting, connected, disconnected, failed, closed
}

/// Watches the game's connections and says when to replace one, counting reconnects over the
/// whole game rather than per connection.
public struct ReconnectWatch: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Keep this connection.
        case keep
        /// Close it and open another: the `attempt`th reconnect (from 1).
        case reconnect(attempt: Int)
        /// Close it: reconnecting has given up.
        case giveUp
    }

    /// Reconnects so far.
    public private(set) var attempt = 0
    private let attempts: Int
    private var openedAt: Int64
    private var connected = false
    private var disconnectedAt: Int64?
    private var over = false

    /// Watching the first connection, opened at `nowMs`.
    public init(nowMs: Int64, attempts: Int = Reconnect.attempts) {
        (openedAt, self.attempts) = (nowMs, attempts)
    }

    /// The current connection is now `state`.
    public mutating func state(_ state: PeerState, nowMs: Int64) -> Verdict {
        guard !over else { return .keep }
        switch state {
        case .connected:
            connected = true
            disconnectedAt = nil
            return .keep
        case .disconnected:
            // Disconnected often recovers by itself; failed never does. Before it has connected
            // the connect timeout covers it.
            if connected, disconnectedAt == nil { disconnectedAt = nowMs }
            return .keep
        case .failed, .closed:
            return replace(nowMs)
        case .new, .connecting:
            return .keep
        }
    }

    /// The current connection's offer was refused, or its answer could not be taken.
    public mutating func offerFailed(nowMs: Int64) -> Verdict {
        over ? .keep : replace(nowMs)
    }

    /// Time passes: call it every second or so.
    public mutating func tick(nowMs: Int64) -> Verdict {
        guard !over else { return .keep }
        if !connected, nowMs - openedAt >= Reconnect.connectTimeoutMs { return replace(nowMs) }
        if let disconnectedAt, nowMs - disconnectedAt >= Reconnect.disconnectedGraceMs { return replace(nowMs) }
        return .keep
    }

    private mutating func replace(_ nowMs: Int64) -> Verdict {
        guard attempt < attempts else {
            over = true
            return .giveUp
        }
        attempt += 1
        (openedAt, connected, disconnectedAt) = (nowMs, false, nil)
        return .reconnect(attempt: attempt)
    }
}
