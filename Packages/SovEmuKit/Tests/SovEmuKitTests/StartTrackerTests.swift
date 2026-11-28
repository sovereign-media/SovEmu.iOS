import Testing
@testable import SovEmuKit

/// One start, as the loading screen follows it, and the session clock that times it.
struct StartTrackerTests {
    private func link(_ state: String, elapsedMs: Int = 0) -> WireProtocol.Link {
        WireProtocol.Link(state: state, elapsedMs: elapsedMs, budgetMs: 2000, path: "lan")
    }

    @Test func theBarNeverMovesBackOverTheWholeStart() {
        var start = StartTracker()
        start.progressed(StartStatus(phase: .content, read: 50, total: 100))
        let reading = start.bar
        #expect(reading > 0.5)
        // A later poll with less (a phase that restarts its count) does not take it back.
        start.progressed(StartStatus(phase: .core))
        #expect(start.bar == reading)
        start.sessionReady()
        #expect(start.bar == 0.85)
        start.connecting(attempt: 0)
        start.linked(link(WireProtocol.Link.probing, elapsedMs: 1000))
        #expect(abs(start.bar - 0.91) < 1e-9)
        // The check begun again, or a reconnect: each starts low, and the bar stays.
        start.linked(link(WireProtocol.Link.probing))
        #expect(abs(start.bar - 0.91) < 1e-9)
        start.connecting(attempt: 1)
        #expect(abs(start.bar - 0.91) < 1e-9)
        #expect(start.screen(title: "T", error: nil) == StartScreen(label: "Reconnecting", fraction: start.bar))
    }

    @Test func aLatePollAfterTheSessionIsReadyChangesNothing() {
        var start = StartTracker()
        start.sessionReady()
        start.connecting(attempt: 0)
        start.progressed(StartStatus(phase: .failed, error: "late"))
        #expect(start.progress == nil)
        #expect(start.screen(title: "T", error: nil)?.label == "Connecting")
    }

    @Test func eachConnectionCountsItsOwnWaitAndCheck() {
        var start = StartTracker()
        start.sessionReady()
        start.connecting(attempt: 0)
        start.linked(link(WireProtocol.Link.done))
        start.waited(6200)
        let screen = start.screen(title: "T", error: nil)
        #expect(screen?.detail == "6 s")
        // The wait moves the bar, so a long boot never looks stuck.
        #expect((screen?.fraction ?? 0) > 0.97 && start.bar == screen?.fraction)
        start.connecting(attempt: 1)
        #expect(start.link == nil && start.waitedMs == 0)
    }

    @Test func thePictureEndsTheLoadingScreenAndItsCount() {
        var start = StartTracker()
        start.sessionReady()
        start.connecting(attempt: 0)
        start.shown()
        start.waited(9000)
        #expect(start.screen(title: "T", error: nil) == nil)
        #expect(start.waitedMs == 0, "a tick after the picture leaves the count alone")
        // A failure still shows over the game.
        #expect(start.screen(title: "T", error: "Lost the connection to the game")?.label == "Lost the connection to the game")
    }

    @Test func givingUpSaysTheGameCouldNotConnect() {
        var start = StartTracker()
        start.sessionReady()
        start.connecting(attempt: 3)
        start.gaveUp()
        #expect(start.screen(title: "T", error: nil)?.label == "Could not connect to the game")
    }

    // MARK: - SessionClock

    @Test func aStillPictureWhilePlayingIsAStallOnce() {
        var clock = SessionClock(nowMs: 10_000)
        #expect(!clock.tick(nowMs: 11_000, frames: 60, playing: true).stalled)
        #expect(!clock.tick(nowMs: 12_000, frames: 60, playing: true).stalled)
        #expect(!clock.tick(nowMs: 13_000, frames: 60, playing: true).stalled)
        let stall = clock.tick(nowMs: 14_000, frames: 60, playing: true)
        #expect(stall == SessionClock.Tick(elapsedMs: 4000, stalled: true))
        #expect(!clock.tick(nowMs: 15_000, frames: 60, playing: true).stalled, "reported once a stall, not every second")
        // Moving again, then still again: a new stall.
        _ = clock.tick(nowMs: 16_000, frames: 61, playing: true)
        _ = clock.tick(nowMs: 18_000, frames: 61, playing: true)
        #expect(clock.tick(nowMs: 19_000, frames: 61, playing: true).stalled)
    }

    @Test func aPauseOrTheStartIsNoStall() {
        var clock = SessionClock(nowMs: 0)
        // Before the first picture (not yet playing), and with the menu open, the picture is
        // still on purpose.
        for s in 1...10 { #expect(!clock.tick(nowMs: Int64(s) * 1000, frames: 0, playing: false).stalled) }
        // Play resumes: the stall is counted from then, not from the last frame before the pause.
        #expect(!clock.tick(nowMs: 11_000, frames: 0, playing: true).stalled)
        #expect(clock.tick(nowMs: 14_000, frames: 0, playing: true).stalled)
    }

    @Test func aLateTickCountsTheTimeNotTheTicks() {
        // A tick held up (the main thread busy) still measures the wait and the stall in time.
        var clock = SessionClock(nowMs: 500)
        _ = clock.tick(nowMs: 1500, frames: 1, playing: true)
        let late = clock.tick(nowMs: 4600, frames: 1, playing: true)
        #expect(late == SessionClock.Tick(elapsedMs: 4100, stalled: true))
    }
}
