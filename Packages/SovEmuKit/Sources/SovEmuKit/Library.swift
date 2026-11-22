import Foundation

// MARK: - The library's models (`Game`, saves, the home feed, collections, patches, cheats)

/// A save of a game: its slot (0 the auto save, 1–9 the player's), when (Unix seconds), and the
/// screen when it was saved, as a URL signed for this user that changes with each save.
public struct SaveSlot: Codable, Sendable, Hashable {
    public let slot: Int
    public let savedAt: Double
    public let screenshotUrl: String?

    public init(slot: Int, savedAt: Double, screenshotUrl: String? = nil) {
        (self.slot, self.savedAt, self.screenshotUrl) = (slot, savedAt, screenshotUrl)
    }

    static let fields = "slot savedAt screenshotUrl"
}

/// What a multi-file game's files are (`PartKind`).
public enum PartKind: String, Codable, Sendable, Hashable {
    case disc = "DISC", disk = "DISK", tape = "TAPE", side = "SIDE", part = "PART"

    public init(from decoder: Decoder) throws {
        // A kind a newer server adds is drawn as a disc.
        self = PartKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .disc
    }
}

/// A game in the library, with everything the screens show: its artwork (`image` a screenshot
/// or composite, `thumb` the box art, `video` a snap, each a URL signed for this user), its game
/// information, and this user's favourite, patch and auto save.
public struct Game: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let system: String
    public let title: String
    /// The file's own title, when the game information names it differently.
    public let fileTitle: String?
    /// No-Intro tags from the file name: "USA", "Rev 1" …
    public let tags: [String]
    /// Its file, relative to the system's folder.
    public let path: String
    /// Bytes (a GraphQL `Float`).
    public let size: Double
    /// `2026-11-19 16:05:56`, UTC.
    public let lastPlayedAt: String?
    public let playCount: Int
    public let image: String?
    public let thumb: String?
    public let video: String?
    public let description: String?
    /// `YYYY-MM-DD`, `YYYY-MM` or `YYYY`.
    public let releaseDate: String?
    public let developer: String?
    public let publisher: String?
    /// Comma-separated: "Platform, Action".
    public let genre: String?
    /// As the game information says it: "1", "1-2", "1 to 4" …
    public let players: String?
    /// 0 to 1.
    public let rating: Double?
    /// How many files it has (discs, disks, tapes…); 1 for most.
    public let discs: Int
    public let partKind: PartKind?
    public var favourite: Bool
    /// What tells it from games of the same title on its system ("Translation", "Rev 1").
    public let release: String?
    /// The soft patch this user plays it with, by name; nil for the original.
    public var patch: String?
    public let autoSave: SaveSlot?

    public init(
        id: Int64, system: String, title: String, fileTitle: String? = nil, tags: [String] = [], path: String = "",
        size: Double = 0, lastPlayedAt: String? = nil, playCount: Int = 0, image: String? = nil, thumb: String? = nil,
        video: String? = nil, description: String? = nil, releaseDate: String? = nil, developer: String? = nil,
        publisher: String? = nil, genre: String? = nil, players: String? = nil, rating: Double? = nil, discs: Int = 1,
        partKind: PartKind? = nil, favourite: Bool = false, release: String? = nil, patch: String? = nil,
        autoSave: SaveSlot? = nil
    ) {
        (self.id, self.system, self.title, self.fileTitle, self.tags, self.path) = (id, system, title, fileTitle, tags, path)
        (self.size, self.lastPlayedAt, self.playCount) = (size, lastPlayedAt, playCount)
        (self.image, self.thumb, self.video, self.description) = (image, thumb, video, description)
        (self.releaseDate, self.developer, self.publisher, self.genre) = (releaseDate, developer, publisher, genre)
        (self.players, self.rating, self.discs, self.partKind) = (players, rating, discs, partKind)
        (self.favourite, self.release, self.patch, self.autoSave) = (favourite, release, patch, autoSave)
    }

    static let fields = """
        id system title fileTitle tags path size lastPlayedAt playCount \
        image: mediaUrl(kind: IMAGE) thumb: mediaUrl(kind: THUMB) video: mediaUrl(kind: VIDEO) \
        description releaseDate developer publisher genre players rating discs partKind favourite release patch \
        autoSave { \(SaveSlot.fields) }
        """

    enum CodingKeys: String, CodingKey {
        case id, system, title, fileTitle, tags, path, size, lastPlayedAt, playCount, image, thumb, video, description
        case releaseDate, developer, publisher, genre, players, rating, discs, partKind, favourite, release, patch, autoSave
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        system = try c.decode(String.self, forKey: .system)
        title = try c.decode(String.self, forKey: .title)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayedAt = try c.decodeIfPresent(String.self, forKey: .lastPlayedAt)
        // What an older server does not send has its plain default: the screens show less.
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        discs = try c.decodeIfPresent(Int.self, forKey: .discs) ?? 1
        favourite = try c.decodeIfPresent(Bool.self, forKey: .favourite) ?? false
        fileTitle = try c.decodeIfPresent(String.self, forKey: .fileTitle)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        video = try c.decodeIfPresent(String.self, forKey: .video)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        developer = try c.decodeIfPresent(String.self, forKey: .developer)
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        players = try c.decodeIfPresent(String.self, forKey: .players)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        partKind = try c.decodeIfPresent(PartKind.self, forKey: .partKind)
        release = try c.decodeIfPresent(String.self, forKey: .release)
        patch = try c.decodeIfPresent(String.self, forKey: .patch)
        autoSave = try c.decodeIfPresent(SaveSlot.self, forKey: .autoSave)
    }

    /// "1996", from the release date.
    public var year: String? {
        guard let date = releaseDate, date.count >= 4 else { return nil }
        let year = String(date.prefix(4))
        return year.allSatisfy(\.isNumber) ? year : nil
    }

    /// "1996 · Nintendo · Platform", from what is known.
    public var byline: String {
        [year, developer ?? publisher, genre].compactMap { $0 }.joined(separator: " · ")
    }
}

/// `Query.home` and this user's collections: the hero's games, recently played (with their
/// auto saves), recently added, favourites, and a row per collection.
public struct HomeFeed: Sendable, Equatable {
    public var featured: [Game]
    public var recent: [Game]
    public var added: [Game]
    public var favourites: [Game]
    public var collections: [HomeCollection]

    public init(featured: [Game] = [], recent: [Game] = [], added: [Game] = [], favourites: [Game] = [],
                collections: [HomeCollection] = []) {
        (self.featured, self.recent, self.added, self.favourites, self.collections) =
            (featured, recent, added, favourites, collections)
    }
}

/// One of this user's collections, with its games (most recently added first).
public struct HomeCollection: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let games: [Game]

    public init(id: Int, name: String, games: [Game]) {
        (self.id, self.name, self.games) = (id, name, games)
    }
}

/// A soft patch for a game (a translation, a fix, a hack; applied as it loads). `isDefault`: it
/// sits beside the game with its name, and applies unless the player chose otherwise.
public struct GamePatch: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let isDefault: Bool

    public init(id: Int, name: String, isDefault: Bool) {
        (self.id, self.name, self.isDefault) = (id, name, isDefault)
    }
}

/// The choice after `current` when stepping through the original (nil) and then `patches`.
public func nextPatch(_ patches: [GamePatch], after current: String?) -> GamePatch? {
    let options: [GamePatch?] = [nil] + patches
    let at = max(0, options.firstIndex { $0?.name == current } ?? 0)
    return options[(at + 1) % options.count]
}

/// Artwork drawn around a game's picture (`Game.decoration`, Batocera's format): an image
/// `width`×`height` with a transparent window `left`/`top`/`right`/`bottom` pixels in from its
/// edges, which the picture shows through.
public struct GameDecoration: Codable, Sendable, Equatable {
    public let url: String
    public let width: Int
    public let height: Int
    public let top: Int
    public let left: Int
    public let bottom: Int
    public let right: Int

    public init(url: String, width: Int, height: Int, top: Int, left: Int, bottom: Int, right: Int) {
        (self.url, self.width, self.height, self.top, self.left, self.bottom, self.right) =
            (url, width, height, top, left, bottom, right)
    }

    /// The image's shape.
    public var aspect: Double { height > 0 ? Double(width) / Double(height) : 16.0 / 9.0 }

    static let fields = "url width height top left bottom right"
}

/// Whether to frame the picture: only when the screen is wider than it, so there are bars to
/// fill (a phone held upright shows the picture alone, as large as it can be).
public func shouldFrame(screenAspect: Double, pictureAspect: Double) -> Bool { screenAspect > pictureAspect * 1.05 }

/// A collection a game can go in, and whether it is in it.
public struct CollectionChoice: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public var member: Bool

    public init(id: Int, name: String, member: Bool) {
        (self.id, self.name, self.member) = (id, name, member)
    }
}

/// One of this user's cheats for a game.
public struct Cheat: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let description: String
    public let code: String
    public let enabled: Bool

    public init(id: Int, description: String, code: String, enabled: Bool) {
        (self.id, self.description, self.code, self.enabled) = (id, description, code, enabled)
    }

    static let fields = "id description code enabled"
}

// MARK: - Systems

extension SystemSummary {
    /// The small status badge on a system's card, if it needs one (as the other clients').
    public var badge: String? {
        if needsGpu && rendering == "OFF" { return "no 3D rendering" }
        if !playable { return "no core" }
        if biosMissing { return "no BIOS" }
        if needsGpu && rendering == "SOFTWARE" { return "software rendering" }
        return nil
    }
}

/// Systems grouped by maker, in the server's order (a maker first appears where its first
/// system does).
public func groupByMaker(_ systems: [SystemSummary]) -> [(maker: String, systems: [SystemSummary])] {
    var groups: [(maker: String, systems: [SystemSummary])] = []
    for system in systems {
        if let at = groups.firstIndex(where: { $0.maker == system.manufacturer }) {
            groups[at].systems.append(system)
        } else {
            groups.append((system.manufacturer, [system]))
        }
    }
    return groups
}

// MARK: - Signed file URLs

/// The query parameters of a signed file URL (the server's `assets.rs`, Sovereign's names).
private let signatureParameters: Set<String> = ["Sov-UserId", "Sov-Expiry", "Sov-Signature"]

/// A file URL without its signature: the same picture's key in the image cache, whichever
/// signature it was fetched with (the server signs URLs afresh each hour). Other parameters,
/// such as a save screenshot's `?t=` (which changes with each save), are kept.
public func assetCacheKey(_ url: String) -> String {
    guard let at = url.firstIndex(of: "?") else { return url }
    let kept = url[url.index(after: at)...].split(separator: "&").filter { part in
        !signatureParameters.contains(String(part.split(separator: "=", maxSplits: 1).first ?? ""))
    }
    return kept.isEmpty ? String(url[..<at]) : String(url[..<at]) + "?" + kept.joined(separator: "&")
}

// MARK: - Starting a game

/// Where a start has got to (`StartPhase`).
public enum StartPhase: String, Codable, Sendable {
    case stopping = "STOPPING", launching = "LAUNCHING", core = "CORE", content = "CONTENT"
    case ready = "READY", failed = "FAILED"
    /// A phase a newer server knows and this app does not.
    case unknown

    public init(from decoder: Decoder) throws {
        self = StartPhase(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// What the server says about a start (the `startProgress` query).
public struct StartStatus: Codable, Sendable, Equatable {
    public let phase: StartPhase
    public let read: Double?
    public let total: Double?
    public let elapsedMs: Double
    public let phaseMs: Double
    public let error: String?

    public init(phase: StartPhase, read: Double? = nil, total: Double? = nil, elapsedMs: Double = 0, phaseMs: Double = 0,
                error: String? = nil) {
        (self.phase, self.read, self.total, self.elapsedMs, self.phaseMs, self.error) =
            (phase, read, total, elapsedMs, phaseMs, error)
    }

    static let fields = "phase read total elapsedMs phaseMs error"
}
