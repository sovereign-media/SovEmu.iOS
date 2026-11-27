import Foundation
import Observation
import SovEmuKit
import SwiftUI

/// What a screen shows while its data loads.
enum Load<T> {
    case loading
    case ready(T)
    case failed(String)

    var value: T? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

/// The app's data, fetched once and kept, as the Android app's `Store`: the signed-in user, the
/// systems, the home feed and each opened system's games (indexed off the main thread). Screens
/// read these, so going back to a screen never waits for the network or re-sorts a list. A game
/// ending refreshes what it changed (play counts, recently played).
///
/// Every request belongs to the current sign-in: `clear` cancels them, so a late answer from the
/// previous account can neither show its data nor sign the next one out.
@MainActor
@Observable
final class Library {
    private(set) var user: User?
    private(set) var systems: Load<[SystemSummary]> = .loading
    private(set) var home: Load<HomeFeed> = .loading
    private var games: [String: Load<GameIndex>] = [:]

    /// How often the lists are fetched again, well inside a signed URL's day.
    private static let refreshEvery: Duration = .seconds(6 * 3600)

    @ObservationIgnored private let api: () -> SovEmuAPI?
    @ObservationIgnored private let signedOut: () -> Void
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(api: @escaping () -> SovEmuAPI?, signedOut: @escaping () -> Void) {
        self.api = api
        self.signedOut = signedOut
    }

    var systemList: [SystemSummary] { systems.value ?? [] }

    func system(_ id: String) -> SystemSummary? { systemList.first { $0.id == id } }

    func refresh() {
        run { await self.loadUser() }
        run { await self.loadSystems() }
        run { await self.loadHome() }
        keepFresh()
    }

    /// The file URLs in these lists are signed for a day (`SOVEMU_ASSET_URL_HOURS`), and the app
    /// may stay open longer: every few hours the lists are fetched again, quietly (what is on
    /// screen stays until the new copy arrives), so their artwork keeps loading.
    private func keepFresh() {
        run {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshEvery)
                guard !Task.isCancelled else { return }
                await self.loadSystems()
                await self.loadHome()
                for system in self.games.keys { await self.loadGames(system, quiet: true) }
            }
        }
    }

    /// A system's games, as far as they have loaded (`want` asks for them).
    func games(_ system: String) -> Load<GameIndex> { games[system] ?? .loading }

    /// Fetches a system's games the first time a screen wants them.
    func want(_ system: String) {
        guard games[system] == nil else { return }
        games[system] = .loading
        run { await self.loadGames(system) }
    }

    /// A random game with a video snap, for the screensaver: a system picked in proportion to its
    /// games (so a big library shows more), then one of its games. Loads (and keeps) that
    /// system's list the first time; nil while there is nothing to show.
    func randomVideoGame() async -> Game? {
        let withGames = systemList.filter { $0.gameCount > 0 }
        guard !withGames.isEmpty else { return nil }
        var pick = Int.random(in: 0..<withGames.reduce(0) { $0 + $1.gameCount })
        guard let system = withGames.first(where: { pick -= $0.gameCount; return pick < 0 }) else { return nil }
        if games[system.id] == nil { games[system.id] = .loading }
        if games[system.id]?.value == nil { await loadGames(system.id) }
        return games[system.id]?.value?.games.filter { $0.video != nil }.randomElement()
    }

    /// After a game: its play count and the home rows changed.
    func played(_ system: String) {
        run { await self.loadHome() }
        if games[system] != nil { run { await self.loadGames(system, quiet: true) } }
    }

    /// Marks `game` as a favourite or not, at once in its system's list (so the panel's heart and
    /// the Favourites filter follow without waiting), then on the server; a failure puts it
    /// back. Home is fetched again either way, for its Favourites row. Returns the error, if any.
    func setFavourite(_ game: Game, _ favourite: Bool) async -> String? {
        await update(game.system, game.id) { $0.favourite = favourite }
        var failure: String?
        do {
            try await api()?.setFavourite(gameId: game.id, favourite: favourite)
        } catch {
            await update(game.system, game.id) { $0.favourite = !favourite }
            failure = note(error)
        }
        run { await self.loadHome() }
        return failure
    }

    /// Plays `game` with `patch` (nil: the original), at once in its system's list (the panel
    /// and its saves follow: a patched game's saves are its own), then on the server; a failure
    /// puts it back. Home is fetched again (its auto saves may differ). Returns the error, if any.
    func setPatch(_ game: Game, _ patch: GamePatch?) async -> String? {
        let before = game.patch
        await update(game.system, game.id) { $0.patch = patch?.name }
        var failure: String?
        do {
            try await api()?.setPatch(gameId: game.id, patchId: patch?.id)
        } catch {
            await update(game.system, game.id) { $0.patch = before }
            failure = note(error)
        }
        run { await self.loadHome() }
        return failure
    }

    /// Collections changed (a game went in or out, or one was made): Home shows a row for each.
    func collectionsChanged() {
        run { await self.loadHome() }
    }

    /// Signed out: forget everything, and cancel what the old sign-in still has in flight.
    func clear() {
        tasks.forEach { $0.cancel() }
        tasks = []
        user = nil
        systems = .loading
        home = .loading
        games = [:]
    }

    // MARK: Loading

    private func run(_ work: @escaping @MainActor () async -> Void) {
        tasks.removeAll { $0.isCancelled }
        tasks.append(Task { await work() })
    }

    private func loadUser() async {
        do {
            user = try await api()?.status().user
        } catch {
            _ = note(error)
        }
    }

    private func loadSystems() async {
        do {
            if let list = try await api()?.systems() { systems = .ready(list) }
        } catch {
            let message = note(error)
            if systems.value == nil { systems = .failed(message) }
        }
    }

    private func loadHome() async {
        do {
            if let feed = try await api()?.home() { home = .ready(feed) }
        } catch {
            let message = note(error)
            if home.value == nil { home = .failed(message) }
        }
    }

    private func loadGames(_ system: String, quiet: Bool = false) async {
        if !quiet { games[system] = .loading }
        do {
            guard let list = try await api()?.games(system: system) else { return }
            let index = await Task.detached(priority: .userInitiated) { GameIndex(list) }.value
            guard !Task.isCancelled else { return }
            games[system] = .ready(index)
        } catch {
            let message = note(error)
            if !quiet { games[system] = .failed(message) }
        }
    }

    /// Changes one game in its system's list (if that list is loaded).
    private func update(_ system: String, _ id: Int64, _ change: @escaping @Sendable (inout Game) -> Void) async {
        guard let index = games[system]?.value else { return }
        let list = index.games.map { game in
            guard game.id == id else { return game }
            var changed = game
            change(&changed)
            return changed
        }
        games[system] = .ready(await Task.detached { GameIndex(list) }.value)
    }

    /// The message to show for `error`; an expired sign-in also signs the app out.
    private func note(_ error: Error) -> String {
        if let error = error as? APIError {
            if error.isUnauthenticated { signedOut() }
            return error.message
        }
        if error is CancellationError { return "" }
        return "Cannot reach the server: \(error.localizedDescription)"
    }
}

/// How a game starts: from a save slot (`continue` is the auto save's), from scratch, or asking
/// (Continue or Start over) when there is an auto save.
enum Start: Hashable {
    case fromSlot(Int)
    case new
    case ask

    static let `continue` = Start.fromSlot(autoSlot)
}

/// The settings the app keeps across launches, as the Android app's.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// A system's games' sort, kept across launches like the other clients'.
    var sort: GameSort {
        didSet { defaults.set(sort.rawValue, forKey: "sort") }
    }
    /// The stats overlay over a game (off by default).
    var stats: Bool {
        didSet { defaults.set(stats, forKey: "stats") }
    }
    /// Background music in the menus (on by default, as on Android; the silent switch mutes it).
    var music: Bool {
        didSet { defaults.set(music, forKey: "music") }
    }
    /// CRT scan lines over the menus (on by default, as on Android).
    var scanlines: Bool {
        didSet { defaults.set(scanlines, forKey: "scanlines") }
    }
    /// Minutes without input before the screensaver (0: never). Five on an iPad, as on Android;
    /// off on an iPhone, where keeping the screen awake for it costs the battery.
    var screensaverMinutes: Int {
        didSet { defaults.set(screensaverMinutes, forKey: "screensaver") }
    }

    /// The screensaver's choices, in minutes without input (0: never).
    static let screensaverChoices = [0, 3, 5, 10]

    init() {
        sort = GameSort(rawValue: defaults.string(forKey: "sort") ?? "") ?? .title
        stats = defaults.bool(forKey: "stats")
        music = defaults.object(forKey: "music") as? Bool ?? true
        scanlines = defaults.object(forKey: "scanlines") as? Bool ?? true
        screensaverMinutes = defaults.object(forKey: "screensaver") as? Int
            ?? (UIDevice.current.userInterfaceIdiom == .pad ? 5 : 0)
    }
}
