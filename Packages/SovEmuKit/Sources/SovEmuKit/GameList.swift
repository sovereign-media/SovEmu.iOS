import Foundation

// A system's game list: searching, filtering, sorting and the A–Z jump, after SovEmu.Web's
// src/lib/games.ts and SovEmu.Android's GameList.kt, so the screen only draws what these return.

public enum GameSort: String, CaseIterable, Sendable, Identifiable {
    case title, recent, year, plays

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .recent: "Recently played"
        case .year: "Release year"
        case .plays: "Most played"
        }
    }
}

public enum PlayedFilter: String, Sendable {
    case played, unplayed
}

public struct GameFilters: Sendable, Equatable {
    public var played: PlayedFilter?
    /// Only games for at least two players.
    public var multiplayer: Bool
    /// Only games in any of these genres.
    public var genres: Set<String>
    /// Only this user's favourites.
    public var favourites: Bool

    public init(played: PlayedFilter? = nil, multiplayer: Bool = false, genres: Set<String> = [], favourites: Bool = false) {
        (self.played, self.multiplayer, self.genres, self.favourites) = (played, multiplayer, genres, favourites)
    }

    /// How many filters are on, for the Filters chip.
    public var count: Int {
        (played != nil ? 1 : 0) + (multiplayer ? 1 : 0) + (favourites ? 1 : 0) + genres.count
    }
}

/// A game's genres: the metadata lists them comma-separated ("Platform, Action").
public func genresOf(_ genre: String?) -> [String] {
    (genre ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// The most players a game takes, from "1-2", "2", "1 to 4" …, or nil when unknown.
public func maxPlayers(_ players: String?) -> Int? {
    (players ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max()
}

/// Folds case and accents, so "pokemon" finds "Pokémon".
public func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
}

/// The letters the jump strip offers: "#" then A–Z.
public let jumpLetters: [String] = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value).map { String(UnicodeScalar($0)!) }

/// The letter a title files under: A–Z, or "#" for digits and symbols. Articles are not skipped.
public func letterOf(_ title: String) -> String {
    guard let c = fold(title).first?.uppercased(), let scalar = c.unicodeScalars.first, c.count == 1,
          ("A"..."Z").contains(String(scalar)) else { return "#" }
    return c
}

/// One system's games, indexed once: each game's folded search text, genres, players, year and
/// letter are worked out here rather than on every keystroke or sort.
public struct GameIndex: Sendable {
    private struct Entry: Sendable {
        let game: Game
        let text: String
        let genres: [String]
        let players: Int?
        let year: Int
        let played: Int64
    }

    public let games: [Game]
    private let entries: [Entry]

    /// Every genre with its count, most common first: empty until game information is fetched.
    public let genreCounts: [(genre: String, count: Int)]
    /// Whether any game says how many players it takes, so the players filter can do something.
    public let knowsPlayers: Bool

    public init(_ games: [Game]) {
        self.games = games
        // In title order, worked out once (collation is the slow part): every other sort is
        // stable, so its ties stay in title order too.
        entries = games.map { g in
            let words = [g.title, g.fileTitle, g.genre, g.developer, g.publisher].compactMap { $0 } + g.tags
            return Entry(
                game: g, text: fold(words.joined(separator: " ")), genres: genresOf(g.genre), players: maxPlayers(g.players),
                year: Int(g.year ?? "") ?? 0, played: GameIndex.playedAt(g.lastPlayedAt))
        }.sorted { GameIndex.titleOrder($0.game.title, $1.game.title) < 0 }
        var counts: [String: Int] = [:]
        for genre in entries.flatMap(\.genres) { counts[genre, default: 0] += 1 }
        genreCounts = counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.genre < $1.genre }
        knowsPlayers = entries.contains { $0.players != nil }
    }

    /// The games matching every word of `query` and every filter, sorted by `sort` (ties by title).
    public func query(_ query: String, filters: GameFilters, sort: GameSort) -> [Game] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = entries.filter { e in
            if filters.played == .played && e.game.playCount == 0 { return false }
            if filters.played == .unplayed && e.game.playCount > 0 { return false }
            if filters.multiplayer && (e.players ?? 1) < 2 { return false }
            if filters.favourites && !e.game.favourite { return false }
            if !filters.genres.isEmpty && !filters.genres.contains(where: e.genres.contains) { return false }
            return words.allSatisfy { e.text.contains($0) }
        }
        // Swift's sort is not stable: the position breaks ties, keeping title order.
        func stable(_ before: (Entry, Entry) -> Bool?) -> [Entry] {
            kept.enumerated().sorted { a, b in before(a.element, b.element) ?? (a.offset < b.offset) }.map(\.element)
        }
        let sorted: [Entry] = switch sort {
        case .title: kept
        case .recent: stable { $0.played == $1.played ? nil : $0.played > $1.played }
        case .year: stable { a, b in
            let (x, y) = (a.year == 0 ? 9999 : a.year, b.year == 0 ? 9999 : b.year)
            return x == y ? nil : x < y
        }
        case .plays: stable { $0.game.playCount == $1.game.playCount ? nil : $0.game.playCount > $1.game.playCount }
        }
        return sorted.map(\.game)
    }

    /// Case- and accent-insensitive, digits by value ("Mega Man 2" before "Mega Man 10"): <0, 0, >0.
    public static func titleOrder(_ a: String, _ b: String) -> Int {
        let x = chunks(a), y = chunks(b)
        for (p, q) in zip(x, y) {
            let c: Int
            if let pd = p.first, pd.isNumber, let qd = q.first, qd.isNumber {
                c = compareNumbers(p, q)
            } else {
                switch p.compare(q, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "")) {
                case .orderedAscending: c = -1
                case .orderedDescending: c = 1
                case .orderedSame: c = 0
                }
            }
            if c != 0 { return c }
        }
        return x.count - y.count
    }

    /// Runs of digits and of everything else.
    private static func chunks(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var digits: Bool?
        for ch in s {
            let d = ch.isASCII && ch.isNumber
            if digits != nil && d != digits {
                out.append(current)
                current = ""
            }
            current.append(ch)
            digits = d
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Two runs of digits by value, however long.
    private static func compareNumbers(_ a: String, _ b: String) -> Int {
        let x = a.drop { $0 == "0" }, y = b.drop { $0 == "0" }
        if x.count != y.count { return x.count < y.count ? -1 : 1 }
        return x == y ? 0 : (x < y ? -1 : 1)
    }

    /// `lastPlayedAt` ("2026-11-19 16:05:56", UTC) as Unix seconds, 0 when never.
    public static func playedAt(_ s: String?) -> Int64 {
        guard let s else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: s) else { return 0 }
        return Int64(date.timeIntervalSince1970)
    }
}

/// The jump strip's stops: only letters some shown game files under, "#" first.
public func jumpStops(_ games: [Game]) -> [String] {
    let present = Set(games.map { letterOf($0.title) })
    return jumpLetters.filter(present.contains)
}

/// Where the jump strip goes for `letter`: the first game under it, else the next letter with
/// one, else the last game; -1 when empty.
public func jumpTo(_ games: [Game], _ letter: String) -> Int {
    guard !games.isEmpty else { return -1 }
    let wanted = jumpLetters.firstIndex(of: letter) ?? 0
    return games.firstIndex { (jumpLetters.firstIndex(of: letterOf($0.title)) ?? 0) >= wanted } ?? games.count - 1
}

/// "3 hours ago", from Unix seconds, against `now`.
public func formatAgo(_ seconds: Int64, now: Int64) -> String {
    guard seconds > 0 else { return "never" }
    let s = max(0, now - seconds)
    func plural(_ n: Int64, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s") ago" }
    switch s {
    case ..<60: return "just now"
    case ..<3600: return plural(s / 60, "minute")
    case ..<86_400: return plural(s / 3600, "hour")
    case ..<(30 * 86_400): return plural(s / 86_400, "day")
    case ..<(365 * 86_400): return plural(s / (30 * 86_400), "month")
    default: return plural(s / (365 * 86_400), "year")
    }
}

private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                      "November", "December"]

/// A release date as people say it: "March 11, 1995", "March 1995" or "1995" (from `YYYY[-MM[-DD]]`).
public func formatReleaseDate(_ date: String?) -> String? {
    guard let parts = date?.split(separator: "-", omittingEmptySubsequences: false).map(String.init),
          let year = parts.first, year.count == 4 else { return nil }
    let month = parts.count > 1 ? Int(parts[1]).flatMap { (1...12).contains($0) ? months[$0 - 1] : nil } : nil
    let day = parts.count > 2 ? Int(parts[2]).flatMap { (1...31).contains($0) ? $0 : nil } : nil
    if let month, let day { return "\(month) \(day), \(year)" }
    if let month { return "\(month) \(year)" }
    return year
}

/// "1 player", "1-2 players", "Up to 4 players" (from the metadata's "1", "1-2", "1 to 4"…); nil when unknown.
public func formatPlayers(_ players: String?) -> String? {
    guard let most = maxPlayers(players), let players else { return nil }
    let trimmed = players.trimmingCharacters(in: .whitespaces)
    if most == 1 { return "1 player" }
    if trimmed.range(of: #"^\d+\s*-\s*\d+$"#, options: .regularExpression) != nil {
        return "\(players.replacingOccurrences(of: " ", with: "")) players"
    }
    if trimmed == String(most) { return "\(most) players" }
    return "Up to \(most) players"
}

/// "1.2 GB", "820 KB".
public func formatSize(_ bytes: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = bytes
    var i = 0
    while v >= 1024 && i < units.count - 1 {
        v /= 1024
        i += 1
    }
    return i == 0 || v >= 100 ? "\(Int64(v)) \(units[i])" : String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), v, units[i])
}

// MARK: - Save slots

/// The auto save's slot: written when a game ends, loaded by Continue.
public let autoSlot = 0

/// The slots a player saves to by hand, as on the other clients.
public let saveSlots = [1, 2, 3, 4]

/// One row of a save or load picker: the slot, its save if there is one, and whether it can be picked.
public struct SlotRow: Sendable, Equatable {
    public let slot: Int
    public let label: String
    public let save: SaveSlot?
    public let enabled: Bool
}

/// The rows for `numbers` given the game's `saves`: a save picker offers every slot (an empty
/// one is written to), a load picker only the ones with a save (`emptyEnabled` false).
public func slotRows(_ saves: [SaveSlot], _ numbers: [Int], emptyEnabled: Bool) -> [SlotRow] {
    numbers.map { n in
        let save = saves.first { $0.slot == n }
        return SlotRow(slot: n, label: n == autoSlot ? "Auto save" : "Slot \(n)", save: save, enabled: save != nil || emptyEnabled)
    }
}
