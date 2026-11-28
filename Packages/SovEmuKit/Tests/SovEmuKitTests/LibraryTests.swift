import Foundation
import Testing
@testable import SovEmuKit

/// The same cases as SovEmu.Android's GameListTest, PatchTest, DecorationTest and
/// AssetCacheKeyTest, and the API's new shapes.
struct LibraryTests {
    private func game(
        _ id: Int64, _ title: String, _ genre: String? = nil, _ players: String? = nil, _ playCount: Int = 0,
        _ lastPlayedAt: String? = nil, _ releaseDate: String? = nil, _ developer: String? = nil, favourite: Bool = false
    ) -> Game {
        Game(id: id, system: "nes", title: title, lastPlayedAt: lastPlayedAt, playCount: playCount, releaseDate: releaseDate,
             developer: developer, genre: genre, players: players, favourite: favourite)
    }

    private var games: [Game] {
        [
            game(1, "Super Mario Bros.", "Platform", "1-2", 3, "2026-11-01 10:00:00", "1985-09-13", "Nintendo"),
            game(2, "Pokémon Red", "RPG", "1", 1, "2026-11-10 10:00:00", "1996-02-27"),
            game(3, "Mega Man 10", "Platform, Action", "1"),
            game(4, "Mega Man 2", "Platform, Action", "1", releaseDate: "1988"),
            game(5, "1942", "Shooter", "1 to 2"),
            game(6, "the Legend of Zelda", "Adventure", favourite: true),
        ]
    }

    private var index: GameIndex { GameIndex(games) }
    private func ids(_ list: [Game]) -> [Int64] { list.map(\.id) }

    private func game(
        _ id: Int64, _ title: String, _ genre: String? = nil, _ players: String? = nil, releaseDate: String? = nil,
        favourite: Bool = false
    ) -> Game {
        game(id, title, genre, players, 0, nil, releaseDate, nil, favourite: favourite)
    }

    @Test func maxPlayersReadsEveryForm() {
        #expect(maxPlayers("1-2") == 2)
        #expect(maxPlayers("1 to 4") == 4)
        #expect(maxPlayers("1") == 1)
        #expect(maxPlayers(nil) == nil)
        #expect(maxPlayers("unknown") == nil)
    }

    @Test func titlesSortNaturallyIgnoringCaseAndAccents() {
        #expect(ids(index.query("", filters: GameFilters(), sort: .title)) == [5, 4, 3, 2, 1, 6])
    }

    @Test func searchFoldsAccentsAndNeedsEveryWord() {
        #expect(ids(index.query("pokemon", filters: GameFilters(), sort: .title)) == [2])
        #expect(ids(index.query("mega action", filters: GameFilters(), sort: .title)) == [4, 3])
        #expect(ids(index.query("nintendo", filters: GameFilters(), sort: .title)) == [1])
        #expect(index.query("mega rpg", filters: GameFilters(), sort: .title).isEmpty)
    }

    @Test func filtersCombine() {
        #expect(ids(index.query("", filters: GameFilters(played: .played), sort: .title)) == [2, 1])
        #expect(ids(index.query("", filters: GameFilters(multiplayer: true), sort: .title)) == [5, 1])
        #expect(ids(index.query("", filters: GameFilters(genres: ["Platform"]), sort: .title)) == [4, 3, 1])
        #expect(ids(index.query("", filters: GameFilters(favourites: true), sort: .title)) == [6])
        #expect(GameFilters(played: .unplayed, genres: ["RPG"]).count == 2)
        #expect(GameFilters(favourites: true).count == 1)
    }

    @Test func sortsFallBackToTitle() {
        #expect(Array(ids(index.query("", filters: GameFilters(), sort: .recent)).prefix(2)) == [2, 1])
        #expect(Array(ids(index.query("", filters: GameFilters(), sort: .year)).prefix(3)) == [1, 4, 2])
        #expect(Array(ids(index.query("", filters: GameFilters(), sort: .plays)).prefix(3)) == [1, 2, 5])
    }

    @Test func genresAreCountedMostCommonFirst() {
        let first = index.genreCounts.first
        #expect(first?.genre == "Platform" && first?.count == 3)
        #expect(index.knowsPlayers)
        #expect(!GameIndex([game(1, "A")]).knowsPlayers)
    }

    @Test func jumpStripStopsAndTargets() {
        let sorted = index.query("", filters: GameFilters(), sort: .title)
        #expect(jumpStops(sorted) == ["#", "M", "P", "S", "T"])
        #expect(jumpTo(sorted, "M") == 1)
        // No game under N: the next letter that has one.
        #expect(jumpTo(sorted, "N") == 3)
        #expect(jumpTo(sorted, "Z") == sorted.count - 1)
        #expect(jumpTo([], "A") == -1)
        #expect(letterOf("1942") == "#")
        #expect(letterOf("Évoland") == "E")
    }

    @Test func formatting() {
        #expect(games[0].byline == "1985 · Nintendo · Platform")
        #expect(formatAgo(1000, now: 1000 + 3 * 3600) == "3 hours ago")
        #expect(formatAgo(0, now: 5) == "never")
        #expect(formatSize(1_137_133_112) == "1.1 GB")
        #expect(formatSize(512) == "512 B")
        #expect(GameIndex.playedAt("2025-11-04 10:00:00") == 1_762_250_400)
        #expect(GameIndex.playedAt(nil) == 0)
    }

    @Test func releaseDatesAndPlayersReadNaturally() {
        #expect(formatReleaseDate("1995-03-11") == "March 11, 1995")
        #expect(formatReleaseDate("1995-03") == "March 1995")
        #expect(formatReleaseDate("1995") == "1995")
        #expect(formatReleaseDate(nil) == nil)
        #expect(formatReleaseDate("unknown") == nil)
        #expect(formatPlayers("1") == "1 player")
        #expect(formatPlayers("1 - 2") == "1-2 players")
        #expect(formatPlayers("4") == "4 players")
        #expect(formatPlayers("1 to 4") == "Up to 4 players")
        #expect(formatPlayers(nil) == nil)
    }

    @Test func slotPickersOfferWhatCanBePicked() {
        let saves = [SaveSlot(slot: autoSlot, savedAt: 1), SaveSlot(slot: 2, savedAt: 2)]
        let load = slotRows(saves, [autoSlot] + saveSlots, emptyEnabled: false)
        #expect(load.map(\.label) == ["Auto save", "Slot 1", "Slot 2", "Slot 3", "Slot 4"])
        #expect(load.map(\.enabled) == [true, false, true, false, false])
        let saving = slotRows(saves, saveSlots, emptyEnabled: true)
        #expect(saving.allSatisfy { $0.enabled })
        #expect(saving.filter { $0.save != nil }.map(\.slot) == [2])
    }

    @Test func patchesStepThroughTheOriginalThenEachAndRoundAgain() {
        let patches = [GamePatch(id: 1, name: "IPS patch", isDefault: true), GamePatch(id: 2, name: "Hard Mode", isDefault: false)]
        #expect(nextPatch(patches, after: nil)?.name == "IPS patch")
        #expect(nextPatch(patches, after: "IPS patch")?.name == "Hard Mode")
        #expect(nextPatch(patches, after: "Hard Mode") == nil, "back to the original")
        #expect(nextPatch(patches, after: "Gone")?.name == "IPS patch", "a patch no longer there starts from the original")
    }

    @Test func decorationsFrameOnlyWhenTheScreenIsWiderThanThePicture() {
        #expect(shouldFrame(screenAspect: 16.0 / 9, pictureAspect: 4.0 / 3))
        #expect(!shouldFrame(screenAspect: 9.0 / 16, pictureAspect: 4.0 / 3), "a phone held upright")
        #expect(!shouldFrame(screenAspect: 4.0 / 3, pictureAspect: 4.0 / 3), "no bars to fill")
        #expect(abs(GameDecoration(url: "u", width: 1920, height: 1080, top: 0, left: 240, bottom: 0, right: 240).aspect - 16.0 / 9) < 0.001)
        #expect(abs(GameDecoration(url: "u", width: 0, height: 0, top: 0, left: 0, bottom: 0, right: 0).aspect - 16.0 / 9) < 0.001)
    }

    @Test func theSignatureIsNotPartOfTheCacheKey() {
        let a = "/media/games/7/thumb?Sov-UserId=1&Sov-Expiry=1700003600&Sov-Signature=ab12"
        let b = "/media/games/7/thumb?Sov-UserId=1&Sov-Expiry=1700007200&Sov-Signature=cd34"
        #expect(assetCacheKey(a) == "/media/games/7/thumb")
        #expect(assetCacheKey(a) == assetCacheKey(b))
        // A save screenshot's URL changes with each save: that must still change the key.
        #expect(assetCacheKey("/media/games/7/saves/1?t=99&Sov-UserId=1&Sov-Expiry=1&Sov-Signature=ab") == "/media/games/7/saves/1?t=99")
        #expect(assetCacheKey("http://h:8080/media/x.png") == "http://h:8080/media/x.png")
    }

    @Test func systemsBadgeWhatStopsThemAndGroupByMaker() {
        func system(_ id: String, _ maker: String, playable: Bool = true, gpu: Bool = false, rendering: String? = nil, bios: Bool = false)
            -> SystemSummary
        {
            SystemSummary(id: id, name: id, short: id, manufacturer: maker, playable: playable, needsGpu: gpu, rendering: rendering,
                          biosMissing: bios)
        }
        #expect(system("psx", "Sony", gpu: true, rendering: "OFF").badge == "no 3D rendering")
        #expect(system("nes", "Nintendo", playable: false).badge == "no core")
        #expect(system("psx", "Sony", bios: true).badge == "no BIOS")
        #expect(system("n64", "Nintendo", gpu: true, rendering: "SOFTWARE").badge == "software rendering")
        #expect(system("nes", "Nintendo").badge == nil)
        let groups = groupByMaker([system("nes", "Nintendo"), system("md", "Sega"), system("snes", "Nintendo")])
        #expect(groups.map(\.maker) == ["Nintendo", "Sega"])
        #expect(groups[0].systems.map(\.id) == ["nes", "snes"])
    }

    @Test func mediaPathsResolveAgainstTheServer() throws {
        let api = SovEmuAPI(baseURL: try #require(URL(string: "http://192.168.1.20:8080")))
        #expect(api.media("/media/games/7/thumb?Sov-Signature=x")?.absoluteString == "http://192.168.1.20:8080/media/games/7/thumb?Sov-Signature=x")
        #expect(api.media("https://cdn.example/x.png")?.absoluteString == "https://cdn.example/x.png")
        #expect(api.media(nil) == nil)
        #expect(api.media("") == nil)
    }

    // MARK: Reading answers

    /// An API whose server answers every request with `json`.
    private func api(_ json: String) -> SovEmuAPI {
        let stub = Stub { _, _ in (200, json) }
        return SovEmuAPI(baseURL: stub.base, session: stub.session)
    }

    @Test func readsAGameWithEverythingTheScreensShow() async throws {
        let games = try await api("""
            {"data":{"search":[\(APITests.game(id: 7, extra: #""system":"psx","fileTitle":"Epic (USA)","path":"Epic.chd","size":7.5e8,"lastPlayedAt":"2026-11-19 16:05:56","playCount":2,"image":"/media/i","thumb":"/media/t","releaseDate":"1996-02","developer":"Dev","genre":"RPG","players":"1-2","rating":0.8,"discs":2,"partKind":"DISC","favourite":true,"release":"Rev 1","patch":"Fix","autoSave":{"slot":0,"savedAt":1700000000.5,"screenshotUrl":"/media/s"}"#))]}}
            """).search("epic")
        let g = try #require(games.first)
        #expect(g.system == "psx" && g.fileTitle == "Epic (USA)" && g.size == 7.5e8 && g.playCount == 2)
        #expect(g.discs == 2 && g.partKind == .disc && g.favourite && g.patch == "Fix" && g.release == "Rev 1")
        #expect(g.autoSave == SaveSlot(slot: 0, savedAt: 1_700_000_000.5, screenshotUrl: "/media/s"))
        #expect(g.year == "1996" && g.byline == "1996 · Dev · RPG")
    }

    @Test func readsStartProgressWithPhasesANewerServerAdds() async throws {
        let status = try await api("""
            {"data":{"startProgress":{"phase":"CONTENT","read":1048576,"total":null,"elapsedMs":3000,"phaseMs":500,"error":null}}}
            """).startProgress(startId: "s")
        #expect(status.phase == .content && status.read == 1_048_576 && status.total == nil)
        let newer = try await api(
            #"{"data":{"startProgress":{"phase":"WARMING","read":null,"total":null,"elapsedMs":0,"phaseMs":0,"error":null}}}"#
        ).startProgress(startId: "s")
        #expect(newer.phase == .unknown)
    }

    @Test func readsCollectionChoicesByNameAndTheDecoration() async throws {
        let choices = try await api("""
            {"data":{"collections":[{"id":2,"name":"couch"},{"id":1,"name":"Arcade"}],"game":{"collectionIds":[2]}}}
            """).collectionChoices(gameId: 7)
        #expect(choices == [CollectionChoice(id: 1, name: "Arcade", member: false), CollectionChoice(id: 2, name: "couch", member: true)])
        let decoration = try await api("""
            {"data":{"game":{"decoration":{"url":"/media/d.png","width":1920,"height":1080,"top":40,"left":240,"bottom":40,"right":240}}}}
            """).decoration(gameId: 7)
        #expect(decoration == GameDecoration(url: "/media/d.png", width: 1920, height: 1080, top: 40, left: 240, bottom: 40, right: 240))
        #expect(try await api(#"{"data":{"game":{"decoration":null}}}"#).decoration(gameId: 7) == nil)
    }
}

/// The same cases as SovEmu.Android's GameStartTest (and SovEmu.Web's launch.test.ts).
struct GameStartTests {
    private let mib = 1024.0 * 1024.0

    private func status(_ phase: StartPhase = .content, read: Double? = nil, total: Double? = nil, elapsedMs: Double = 0,
                        phaseMs: Double = 0, error: String? = nil) -> StartStatus {
        StartStatus(phase: phase, read: read, total: total, elapsedMs: elapsedMs, phaseMs: phaseMs, error: error)
    }

    @Test func theBarIsExactWhenTheTotalIsKnown() {
        let half = describeStart(status(read: 32 * mib, total: 64 * mib, elapsedMs: 5000))
        #expect(half.label == "Loading the game")
        #expect(half.detail == "32 of 64 MB · 5 s")
        #expect(abs(half.fraction - (0.18 + 0.67 / 2)) < 1e-9)
    }

    @Test func itEasesForwardAndCountsBytesWhenTheTotalIsNotKnown() {
        let early = describeStart(status(read: 3 * mib, phaseMs: 1000))
        let later = describeStart(status(read: 250 * mib, phaseMs: 30000))
        #expect(early.detail == "3 MB read")
        #expect(later.detail == "250 MB read")
        #expect(later.fraction > early.fraction && later.fraction < 0.85)
    }

    @Test func megabytesKeepOneDecimalBelow100() {
        #expect(describeStart(status(read: 1.5 * mib)).detail == "1.5 MB read")
        #expect(describeStart(status(read: 0)).detail == "", "no count before the first byte")
    }

    @Test func itNamesEveryPhaseAndReportsFailure() {
        #expect(describeStart(status(.stopping)).label == "Saving your last game")
        #expect(abs(describeStart(status(.core)).fraction - 0.12) < 1e-9)
        // Ready leaves the bar's last stretch to checking the connection and the first picture.
        #expect(describeStart(status(.ready)).fraction == 0.85)
        let failed = describeStart(status(.failed, error: "no core installed"))
        #expect([failed.label, failed.detail] == ["Could not start", "no core installed"])
        #expect(describeStart(status(.unknown)).fraction == 0, "a phase this app does not know leaves the bar alone")
    }

    @Test func theBarNeverMovesBackwards() {
        var bar = ForwardOnly()
        #expect(bar.next(0.5) == 0.5)
        #expect(bar.next(0.3) == 0.5)
        #expect(bar.next(2) == 1)
    }

    @Test func idsAreOnesTheServerAccepts() {
        #expect(newStartId().range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil)
    }

    @Test func waitingForTheFirstPictureCountsTheWaitAndSaysHowToLeave() {
        #expect(describeFirstPicture(waitedMs: 0) == LaunchView(label: "Starting the game", detail: "", fraction: 0.97))
        #expect(describeFirstPicture(waitedMs: 500).detail == "")
        #expect(describeFirstPicture(waitedMs: 6200).detail == "6 s")
        #expect(describeFirstPicture(waitedMs: 21_000).detail == "21 s · still no picture: ☰ opens the menu")
    }

    private func link(_ state: String = "probing", elapsedMs: Int = 0, budgetMs: Int = 2000, path: String = "")
        -> WireProtocol.Link {
        WireProtocol.Link(state: state, elapsedMs: elapsedMs, budgetMs: budgetMs, path: path)
    }

    @Test func checkingTheConnectionMovesTheBarFromReadyToAlmostFull() {
        // The worker sends no video while it checks: without this stage the bar would sit at
        // "Ready" for up to two seconds with nothing said.
        #expect(abs(describeLink(link()).fraction - 0.85) < 1e-9)
        #expect(abs(describeLink(link(elapsedMs: 1000)).fraction - 0.91) < 1e-9)
        #expect(abs(describeLink(link(elapsedMs: 5000)).fraction - 0.97) < 1e-9)
        #expect(abs(describeLink(link(budgetMs: 0)).fraction - 0.97) < 1e-9)
        #expect(describeLink(link()).label == "Checking your connection")
    }

    @Test func itSaysItIsConnectingUntilTheWorkerIsReached() {
        // Otherwise the screen read "Starting the game" for a second or two before it went back
        // to checking the connection.
        #expect(describeConnecting(waitedMs: 0) == LaunchView(label: "Connecting", detail: "", fraction: 0.85))
        #expect(describeConnecting(waitedMs: 500).detail == "")
        #expect(describeConnecting(waitedMs: 4200).detail == "4 s")
    }

    @Test func theBarCreepsThroughTheStretchesWhoseEndCannotBeKnown() {
        // Connecting: from 0.85, a little way, never into the check's stretch beyond 0.88.
        let connecting = [0, 1000, 5000, 60_000].map { describeConnecting(waitedMs: Int64($0)).fraction }
        #expect(zip(connecting, connecting.dropFirst()).allSatisfy { $0 < $1 })
        #expect(connecting.last! < 0.88)
        // The first picture: from 0.97, never quite full.
        let picture = [0, 2000, 10_000, 120_000].map { describeFirstPicture(waitedMs: Int64($0)).fraction }
        #expect(abs(picture[0] - 0.97) < 1e-9)
        #expect(zip(picture, picture.dropFirst()).allSatisfy { $0 < $1 })
        #expect(picture.last! < 1)
    }

    @Test func itLeavesWhereThePlayerIsToTheNetworkChip() {
        // The chip in the corner says Home network or Remote; the bar's detail stays free for the wait.
        #expect(describeLink(link(path: "lan")).detail == "")
        #expect(describeFirstPicture(waitedMs: 4000).detail == "4 s")
    }

    @Test func theBackgroundShowsWhereThePlayerLeftOffElseTheGameElseItsBoxBlurred() {
        // Continuing: the save's own screenshot, so the player sees where they will be.
        #expect(loadingBackground(saveShot: "save.png", image: "shot.webp", boxArt: "box.webp")
            == LoadingBackground(url: "save.png", pixelated: true, blurred: false))
        #expect(loadingBackground(saveShot: nil, image: "shot.webp", boxArt: "box.webp")
            == LoadingBackground(url: "shot.webp", pixelated: false, blurred: false))
        #expect(loadingBackground(saveShot: "", image: nil, boxArt: "box.webp")
            == LoadingBackground(url: "box.webp", pixelated: false, blurred: true))
        #expect(loadingBackground(saveShot: nil, image: nil, boxArt: nil) == nil, "the system's colour")
    }

    @Test func theStatusLineNamesTheCoreAndThePictureAsTheWebDoes() {
        #expect(loadingStatus(core: "FCEUmm", width: 256, height: 224, fps: 60.0988) == "FCEUmm · 256×224 @ 60.10 fps")
    }

    private func screen(error: String? = nil, progress: StartStatus? = nil, bar: Double = 0, ready: Bool = false,
                        link: WireProtocol.Link? = nil, pictureShown: Bool = false, waitedMs: Int64 = 0) -> StartScreen? {
        GameStart.screen(title: "THPS3", error: error, progress: progress, bar: bar, ready: ready, link: link,
                         pictureShown: pictureShown, waitedMs: waitedMs)
    }

    @Test func theScreenFollowsTheWholeStart() {
        #expect(screen() == StartScreen(label: "Starting THPS3…", fraction: 0))
        #expect(screen(progress: status(read: 32 * mib, total: 64 * mib, elapsedMs: 5000), bar: 0.6)
            == StartScreen(label: "Loading the game", detail: "32 of 64 MB · 5 s", fraction: 0.6))
        #expect(screen(progress: status(.failed, error: "no core installed"), bar: 0.4)
            == StartScreen(label: "Could not start", detail: "no core installed"))
        #expect(screen(progress: status(.ready), bar: 0.85, ready: true) == StartScreen(label: "Connecting", fraction: 0.85))
        let checking = screen(ready: true, link: link(elapsedMs: 1000, path: "lan"))
        #expect(checking?.label == "Checking your connection" && checking?.detail == "")
        #expect(abs((checking?.fraction ?? 0) - 0.91) < 1e-9)
        #expect(screen(ready: true, link: link("done", path: "relay-udp"))
            == StartScreen(label: "Starting the game", fraction: 0.97))
        // A check started again (the pair changed) does not take the bar back.
        #expect(screen(bar: 0.95, ready: true, link: link(elapsedMs: 0))?.fraction == 0.95)
        #expect(screen(ready: true, pictureShown: true, waitedMs: 30_000) == nil, "the first picture ends it")
        #expect(screen(error: "Connection failed", ready: true, pictureShown: true) == StartScreen(label: "Connection failed"))
    }
}

/// The same cases as SovEmu.Android's FrameLatencyTest and LatencyHistoryTest.
struct LatencyTests {
    /// Frame `n` (1-based): planned to render at 5000 + 16n ms, captured at 900 + 16n ms.
    private func render(_ n: Int64) -> Int64 { 5_000 + 16 * n }
    private func captureNs(_ n: Int64) -> Int64 { (900 + 16 * n) * 1_000_000 }
    private func out(_ n: Int64) -> Int64 { render(n) * 1_000_000 }

    private func warmUp(_ latency: FrameLatency, _ n: Int64, nowMs: Int64) {
        for i in 1...n {
            latency.frameEntered(renderTimeMs: render(i), captureTimeNs: captureNs(i), nowMs: nowMs)
            latency.frameDelivered(timestampNs: out(i), nowMs: nowMs)
        }
    }

    @Test func nothingIsMeasuredBeforeAnAck() {
        let latency = FrameLatency()
        latency.frameDelivered(timestampNs: 0, nowMs: 100)
        #expect(latency.medianMs() == nil && latency.count == 0)
    }

    @Test func theFrameThatEnteredAfterTheAckCountsNotOlderOnesStillInside() {
        let latency = FrameLatency()
        warmUp(latency, 3, nowMs: 900)
        #expect(latency.match == .renderTime)
        latency.frameEntered(renderTimeMs: render(4), captureTimeNs: captureNs(4), nowMs: 1_005)
        latency.frameEntered(renderTimeMs: render(5), captureTimeNs: captureNs(5), nowMs: 1_010)
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_020)
        latency.frameEntered(renderTimeMs: render(6), captureTimeNs: captureNs(6), nowMs: 1_025)
        latency.frameDelivered(timestampNs: out(4), nowMs: 1_030)
        latency.frameDelivered(timestampNs: out(5), nowMs: 1_040)
        #expect(latency.medianMs() == nil)
        latency.frameDelivered(timestampNs: out(6), nowMs: 1_052)
        #expect(latency.medianMs() == 52 && latency.count == 1)
    }

    @Test func aLaterFrameCountsWhenTheBoundOneWasDropped() {
        let latency = FrameLatency()
        warmUp(latency, 3, nowMs: 900)
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_010)
        latency.frameEntered(renderTimeMs: render(4), captureTimeNs: captureNs(4), nowMs: 1_015)
        latency.frameEntered(renderTimeMs: render(5), captureTimeNs: captureNs(5), nowMs: 1_030)
        latency.frameDelivered(timestampNs: out(5), nowMs: 1_045)
        #expect(latency.medianMs() == 45)
    }

    @Test func captureTimesMatchWhenTheOutputCarriesThem() {
        let latency = FrameLatency()
        for i in Int64(1)...2 {
            latency.frameEntered(renderTimeMs: render(i), captureTimeNs: captureNs(i), nowMs: 900)
            latency.frameDelivered(timestampNs: captureNs(i), nowMs: 900)
        }
        #expect(latency.match == .captureTime)
        latency.frameEntered(renderTimeMs: render(3), captureTimeNs: captureNs(3), nowMs: 1_000)
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_005)
        latency.frameEntered(renderTimeMs: render(4), captureTimeNs: captureNs(4), nowMs: 1_010)
        latency.frameDelivered(timestampNs: captureNs(3), nowMs: 1_020)
        #expect(latency.medianMs() == nil)
        latency.frameDelivered(timestampNs: captureNs(4), nowMs: 1_036)
        #expect(latency.medianMs() == 36)
    }

    @Test func withoutAMatchingTimestampTheNthFrameInIsTheNthOut() {
        let latency = FrameLatency()
        let n = FrameLatency.learnFrames
        for i in 1...n {
            latency.frameEntered(renderTimeMs: render(i), captureTimeNs: captureNs(i), nowMs: 900)
            latency.frameDelivered(timestampNs: 77_000_000 * i, nowMs: 900)
        }
        #expect(latency.match == .count)
        latency.frameEntered(renderTimeMs: render(n + 1), captureTimeNs: captureNs(n + 1), nowMs: 1_000)
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_001)
        latency.frameEntered(renderTimeMs: render(n + 2), captureTimeNs: captureNs(n + 2), nowMs: 1_002)
        latency.frameDelivered(timestampNs: 1, nowMs: 1_020)
        #expect(latency.medianMs() == nil)
        latency.frameDelivered(timestampNs: 2, nowMs: 1_040)
        #expect(latency.medianMs() == 40)
    }

    @Test func theOldestPendingAckIsKeptAndAStaleOneDropped() {
        let latency = FrameLatency()
        warmUp(latency, 1, nowMs: 900)
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_010)
        latency.ackArrived(clientTimeMs: 1_008, nowMs: 1_012)
        latency.frameEntered(renderTimeMs: render(2), captureTimeNs: captureNs(2), nowMs: 1_015)
        latency.frameDelivered(timestampNs: out(2), nowMs: 1_050)
        #expect(latency.medianMs() == 50)

        let stale = FrameLatency()
        warmUp(stale, 1, nowMs: 900)
        stale.ackArrived(clientTimeMs: 1_000, nowMs: 1_010)
        stale.frameEntered(renderTimeMs: render(2), captureTimeNs: captureNs(2), nowMs: 1_015)
        stale.frameDelivered(timestampNs: out(2), nowMs: 3_100)
        #expect(stale.medianMs() == nil)
        stale.ackArrived(clientTimeMs: 4_000, nowMs: 4_010)
        stale.frameEntered(renderTimeMs: render(3), captureTimeNs: captureNs(3), nowMs: 4_015)
        stale.frameDelivered(timestampNs: out(3), nowMs: 4_030)
        #expect(stale.medianMs() == 30)
    }

    @Test func whenNoFramesAreSeenGoingInTheFirstFrameOutCounts() {
        // As on iOS, where WebRTC decodes out of sight.
        let latency = FrameLatency()
        latency.ackArrived(clientTimeMs: 1_000, nowMs: 1_010)
        latency.frameDelivered(timestampNs: 123, nowMs: 1_039)
        latency.frameDelivered(timestampNs: 456, nowMs: 1_056)
        #expect(latency.medianMs() == 39 && latency.count == 1)
    }

    @Test func theClockWrapsAt32Bits() {
        let latency = FrameLatency()
        latency.ackArrived(clientTimeMs: 0xffff_fff0, nowMs: 0xffff_fff8)
        latency.frameDelivered(timestampNs: 1, nowMs: 0x10)
        #expect(latency.medianMs() == 32)
    }

    @Test func onlyTheLastSamplesCountAndTheMedianIsTheMiddleOne() {
        let latency = FrameLatency(capacity: 3)
        for (i, ms) in [Int64(500), 10, 30, 20].enumerated() {
            let t = Int64(i) * 3_000
            latency.ackArrived(clientTimeMs: t, nowMs: t)
            latency.frameDelivered(timestampNs: 1, nowMs: t + ms)
        }
        #expect(latency.count == 3 && latency.medianMs() == 20)
    }

    @Test func percentilesAreNearestRank() {
        let values = (1...100).map(Int64.init)
        #expect(percentile(values, 50) == 50 && percentile(values, 95) == 95)
        #expect(percentile([7], 95) == 7 && percentile([], 50) == nil)
    }

    @Test func theGraphKeepsTheLastMinuteAndScalesIn25msSteps() {
        var empty = LatencyHistory()
        #expect(empty.size == 0 && empty.scaleMaxMs() == 50 && empty.latestMeasured == nil)
        var ring = LatencyHistory(capacity: 3)
        for i in 1...5 { ring.add(measured: Double(i), estimated: Double(i) * 10) }
        #expect(ring.size == 3)
        #expect((0..<3).map(ring.measured) == [3, 4, 5])
        #expect((0..<3).map(ring.estimated) == [30, 40, 50])
        #expect(ring.latestMeasured == 5)
        var gaps = LatencyHistory()
        gaps.add(measured: nil, estimated: 40)
        #expect(gaps.measured(0).isNaN && gaps.latestMeasured == nil)
        var scale = LatencyHistory()
        scale.add(measured: 30, estimated: 49)
        #expect(scale.scaleMaxMs() == 50)
        scale.add(measured: 51, estimated: nil)
        #expect(scale.scaleMaxMs() == 75)
        scale.add(measured: nil, estimated: 100)
        #expect(scale.scaleMaxMs() == 100)
        scale.add(measured: 101, estimated: 20)
        #expect(scale.scaleMaxMs() == 125)
        scale.clear()
        #expect(scale.size == 0 && scale.scaleMaxMs() == 50)
        empty.add(measured: 1, estimated: 1)
    }
}

/// The overlay's rows, as SovEmu.Android's StreamStatsTest checks them.
struct StatsRowsTests {
    @Test func theSampleCarriesTheRoundTripAndTheEstimate() {
        var sampler = StatsSampler()
        _ = sampler.sample(StatsReading(at: 0))
        let stats = sampler.sample(
            StatsReading(at: 1, bytesReceived: 125_000, jitterBufferDelay: 0.6, jitterBufferEmittedCount: 60,
                         totalDecodeTime: 0.12, framesDecoded: 60),
            inputRtts: [30, 10, 20], inputToFrameMs: 39)
        #expect(stats.kbps == 1000)
        #expect(stats.inputRttP50Ms == 20 && stats.inputRttP95Ms == 30 && stats.inputToFrameMs == 39)
        #expect(abs((stats.estimateMs ?? 0) - (20 + 8 + 2 + 10 + 2 + 8)) < 1e-9)
        let json = String(decoding: WireProtocol.encodeStats(stats).dropFirst(2), as: UTF8.self)
        #expect(json.hasPrefix(#"{"estimate_ms":50,"input_to_frame_ms":39,"input_rtt_p50_ms":20,"input_rtt_p95_ms":30,"#))
    }

    @Test func theOverlayShowsADashForWhatIsUnknown() {
        let rows = Dictionary(uniqueKeysWithValues: WireProtocol.Stats(netRttMs: 4.25, width: 256, height: 240, fps: 60).rows()
            .map { ($0.label, $0.value) })
        #expect(rows["Input round trip"] == "–")
        #expect(rows["Bitrate"] == "–")
        #expect(rows["Measured button→frame"] == "–")
        #expect(rows["Video"] == "256×240 @ 60 fps")
        #expect(rows["Network RTT"] == "4.3 ms" || rows["Network RTT"] == "4.2 ms")
        let order = WireProtocol.Stats().rows().prefix(2).map(\.label)
        #expect(order == ["Estimated button→pixel", "Measured button→frame"])
        #expect(WireProtocol.Stats(inputToFrameMs: 39).rows()[1].value == "39 ms")
    }

    @Test func theStreamRowsNameTheCodecEncoderRendererAudioAndRunAhead() {
        #expect(WireProtocol.pipelineRows(nil, decoder: "x").isEmpty)
        let pipeline = WireProtocol.Pipeline(
            renderer: "llvmpipe (LLVM 19.1.7, 256 bits)", rendererSoftware: true,
            video: .init(codec: "vp8", encoder: "libvpx", hardware: false,
                         fallbacks: [.init(encoder: "nvenc", reason: "no device"), .init(encoder: "x264", reason: "failed")]),
            audio: .init(codec: "opus", sourceHz: 32040.5, kbps: 128), runAhead: 2)
        let rows = Dictionary(uniqueKeysWithValues: WireProtocol.pipelineRows(pipeline, decoder: "VideoToolbox").map { ($0.label, $0.value) })
        #expect(rows["Stream"] == "VP8 · libvpx (CPU)")
        #expect(rows["Fell back from"] == "NVENC: no device; x264: failed")
        #expect(rows["Rendering"] == "Software · llvmpipe (LLVM 19.1.7, 256 bits)")
        #expect(rows["Audio"] == "Opus 128 kbps · from 32,041 Hz" || rows["Audio"] == "Opus 128 kbps · from 32,040 Hz")
        #expect(rows["Run-ahead"] == "2 frames")
        #expect(rows["Decoder"] == "VideoToolbox")
        #expect(WireProtocol.pipelineRows(WireProtocol.Pipeline(runAhead: 1), decoder: nil).last?.value == "1 frame")
    }
}
