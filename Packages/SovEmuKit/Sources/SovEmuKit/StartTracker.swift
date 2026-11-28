import Foundation

// One start of a game, from the tap to the first picture, as the loading screen follows it: the
// server's progress, the session being ready, each connection (and reconnect), the worker's
// check of the connection, the wait for the picture. The one owner of the bar (`ForwardOnly`,
// as SovEmu.Android's player has it), so nothing that reports less (a later phase starting low,
// a check begun again, a new connection) takes it back.

/// What the loading screen shows, kept as the start moves on. Changed on the main thread, by the
/// player; `screen` is what it draws.
public struct StartTracker: Sendable {
    /// The server's word on how far the start has got: nil until it has said.
    public private(set) var progress: StartStatus?
    /// The session has started: the server's part is over.
    public private(set) var ready = false
    /// The worker's check of this connection (`0x83`), as it last said; nil for a new one.
    public private(set) var link: WireProtocol.Link?
    /// How long this connection has waited for its first picture.
    public private(set) var waitedMs: Int64 = 0
    /// Reconnects so far, and whether reconnecting gave up.
    public private(set) var attempt = 0
    public private(set) var connectionFailed = false
    public private(set) var pictureShown = false
    /// The furthest the bar has been.
    public private(set) var bar = 0.0
    private var forward = ForwardOnly()

    public init() {}

    /// The server's progress; late polls once the session is ready change nothing.
    public mutating func progressed(_ status: StartStatus) {
        guard !ready else { return }
        progress = status
        advance()
    }

    public mutating func sessionReady() {
        ready = true
        advance()
    }

    /// A connection begins: the first (`attempt` 0) or a reconnect. Its check and its wait for
    /// a picture start again; the bar stays where it got to.
    public mutating func connecting(attempt: Int) {
        self.attempt = attempt
        link = nil
        waitedMs = 0
        advance()
    }

    /// The worker's check of the connection moved on (the stream drops a stale report).
    public mutating func linked(_ link: WireProtocol.Link) {
        self.link = link
        advance()
    }

    /// The session clock's tick: this connection has waited `ms` for its picture.
    public mutating func waited(_ ms: Int64) {
        guard !pictureShown else { return }
        waitedMs = ms
    }

    public mutating func shown() {
        pictureShown = true
    }

    /// Reconnecting gave up.
    public mutating func gaveUp() {
        connectionFailed = true
    }

    /// The loading screen, or nil once the picture is up; `error` (a failure to start, or a
    /// lost connection) wins.
    public func screen(title: String, error: String?) -> StartScreen? {
        GameStart.screen(title: title, error: error, progress: progress, bar: bar, ready: ready, link: link,
                         pictureShown: pictureShown, waitedMs: waitedMs, attempt: attempt,
                         connectionFailed: connectionFailed)
    }

    /// Takes the bar to where the start now is, if that is further: the server's phase until the
    /// session is ready (the screen draws the bar it is given), then the screen's own stretch.
    private mutating func advance() {
        let fraction = ready ? screen(title: "", error: nil)?.fraction : progress.map { describeStart($0).fraction }
        guard let fraction else { return }
        bar = forward.next(fraction)
    }
}

/// One connection's clock, ticked once a second on the system's uptime: how long it has waited
/// for a first picture (the loading screen's count), and whether a picture that was moving has
/// stopped (`STREAM_STALLED`, once a stall). The same tick samples the stats and drives the
/// reconnect watch, so all of them agree on what a second is.
public struct SessionClock: Sendable {
    /// No new frame for this long, while playing, is a stall.
    public static let stallMs: Int64 = 3000

    /// What one tick found.
    public struct Tick: Equatable, Sendable {
        /// Since the connection began.
        public let elapsedMs: Int64
        /// The picture has just been still for `stallMs` while playing: report it (once).
        public let stalled: Bool
    }

    private let startedMs: Int64
    private var lastFrames: Int64 = -1
    /// When the picture last moved, or play last resumed.
    private var movedMs: Int64
    private var reported = false

    public init(nowMs: Int64) {
        startedMs = nowMs
        movedMs = nowMs
    }

    /// A tick at `nowMs`: `frames` shown so far; `playing` while connected, past the first
    /// picture and not paused in the menu (a still picture then is the game's own choice).
    public mutating func tick(nowMs: Int64, frames: Int64, playing: Bool) -> Tick {
        if !playing || frames != lastFrames {
            movedMs = nowMs
            reported = false
        }
        lastFrames = frames
        let stalled = !reported && nowMs - movedMs >= Self.stallMs
        if stalled { reported = true }
        return Tick(elapsedMs: nowMs - startedMs, stalled: stalled)
    }
}
