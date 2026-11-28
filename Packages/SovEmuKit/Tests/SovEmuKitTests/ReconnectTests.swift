import Testing
@testable import SovEmuKit

/// Reconnecting as the web does: the same constants, the same three reasons, then giving up. The
/// cases of SovEmu.Android's ReconnectTest, driven by states and ticks instead of a test clock.
struct ReconnectTests {
    @Test func aConnectionThatStaysUpIsNeverReplaced() {
        var watch = ReconnectWatch(nowMs: 0)
        #expect(watch.state(.connecting, nowMs: 10) == .keep)
        #expect(watch.state(.connected, nowMs: 500) == .keep)
        for minute in 1...10 { #expect(watch.tick(nowMs: Int64(minute) * 60_000) == .keep) }
        #expect(watch.attempt == 0)
    }

    @Test func aFailedConnectionIsMadeAgainAtOnce() {
        var watch = ReconnectWatch(nowMs: 0)
        _ = watch.state(.connected, nowMs: 500)
        #expect(watch.state(.failed, nowMs: 900) == .reconnect(attempt: 1))
    }

    @Test func aDisconnectionIsGivenFiveSecondsToRecover() {
        var watch = ReconnectWatch(nowMs: 0)
        _ = watch.state(.connected, nowMs: 0)
        _ = watch.state(.disconnected, nowMs: 1_000)
        #expect(watch.tick(nowMs: 1_000 + Reconnect.disconnectedGraceMs - 1) == .keep)
        _ = watch.state(.connected, nowMs: 1_000 + Reconnect.disconnectedGraceMs - 1)
        #expect(watch.tick(nowMs: 60_000) == .keep, "it recovered by itself")

        _ = watch.state(.disconnected, nowMs: 70_000)
        #expect(watch.tick(nowMs: 70_000 + Reconnect.disconnectedGraceMs + 1) == .reconnect(attempt: 1))
    }

    @Test func aConnectionNeverMadeWithinFifteenSecondsIsMadeAgain() {
        var watch = ReconnectWatch(nowMs: 0)
        _ = watch.state(.connecting, nowMs: 100)
        // Disconnected before it ever connected: the connect timeout still decides.
        _ = watch.state(.disconnected, nowMs: 200)
        #expect(watch.tick(nowMs: Reconnect.connectTimeoutMs - 1) == .keep)
        #expect(watch.tick(nowMs: Reconnect.connectTimeoutMs + 1) == .reconnect(attempt: 1))
        // The new connection has its own fifteen seconds.
        #expect(watch.tick(nowMs: Reconnect.connectTimeoutMs + 2) == .keep)
    }

    @Test func afterThreeReconnectsItGivesUp() {
        var watch = ReconnectWatch(nowMs: 0)
        #expect(watch.offerFailed(nowMs: 1) == .reconnect(attempt: 1))
        #expect(watch.offerFailed(nowMs: 2) == .reconnect(attempt: 2))
        #expect(watch.offerFailed(nowMs: 3) == .reconnect(attempt: 3))
        #expect(watch.offerFailed(nowMs: 4) == .giveUp)
        // Given up, nothing more is asked for.
        #expect(watch.tick(nowMs: 60_000) == .keep)
        #expect(watch.state(.failed, nowMs: 60_001) == .keep)
    }

    @Test func reconnectsCountOverTheWholeGameNotPerConnection() {
        var watch = ReconnectWatch(nowMs: 0)
        var verdicts: [ReconnectWatch.Verdict] = []
        for i in 0..<4 {
            _ = watch.state(.connected, nowMs: Int64(i) * 1_000)
            verdicts.append(watch.state(.failed, nowMs: Int64(i) * 1_000 + 500))
        }
        #expect(verdicts == [.reconnect(attempt: 1), .reconnect(attempt: 2), .reconnect(attempt: 3), .giveUp])
    }

    @Test func theLoadingScreenSaysReconnectingThenThatItCouldNotConnect() {
        // The web's words: "Reconnecting" on the bar, then the failure with how to leave.
        #expect(describeConnecting(waitedMs: 500, attempt: 1).label == "Reconnecting")
        let screen = GameStart.screen(title: "T", error: nil, progress: nil, bar: 0.9, ready: true, pictureShown: false,
                                      waitedMs: 0, attempt: 3, connectionFailed: true)
        #expect(screen?.label == "Could not connect to the game")
        #expect(screen?.fraction == nil, "a failure has no bar")
        #expect(screen?.detail.hasPrefix("The server's game ports may be unreachable from here") == true)
    }
}
