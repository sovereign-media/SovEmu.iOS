import ApolloAPI
import Foundation

// MARK: - Generated types → the app's models
//
// The generated types (`Generated/`, internal) stop here: everything outside SovEmuKit sees only
// the models in `API.swift` and `Library.swift`. An enum value a newer server adds maps to the
// model's own fallback rather than failing the answer.

extension GraphQLEnum {
    /// The value's name as the schema spells it, known to this app or not.
    var name: String { rawValue }
}

extension User {
    init(_ f: SovEmuGraphQL.UserFields) {
        // A role a newer server adds grants nothing more than viewing.
        self.init(
            id: Int64(f.id), username: f.username, isAdmin: f.isAdmin, role: Role(rawValue: f.role.name) ?? .viewer)
    }
}

extension AuthStatus {
    init(_ v: SovEmuGraphQL.ViewerQuery.Data.Viewer) {
        self.init(setupRequired: v.setupRequired, user: v.user.map { User($0.fragments.userFields) })
    }
}

extension BootstrapConfig {
    init(_ c: SovEmuGraphQL.BootstrapQuery.Data.BootstrapConfig) {
        self.init(
            signInAvailable: c.signInAvailable, address: c.address, issuer: c.issuer, webClientId: c.webClientId,
            deviceClientId: c.deviceClientId, authorizationEndpoint: c.authorizationEndpoint,
            tokenEndpoint: c.tokenEndpoint, revocationEndpoint: c.revocationEndpoint, deviceAuthorizationEndpoint: c.deviceAuthorizationEndpoint,
            verificationUri: c.verificationUri, passwordEndpoint: c.passwordEndpoint,
            mobileClientId: c.mobileClientId, mobileRedirectUri: c.mobileRedirectUri)
    }
}

extension ClientConfig {
    /// `iceServers` is the `JSON` scalar, holding `RTCIceServer` objects.
    init(_ c: SovEmuGraphQL.ClientConfigQuery.Data.ClientConfig) throws {
        do {
            self.init(iceServers: try c.iceServers.decode([IceServer].self))
        } catch {
            throw APIError(status: 200, message: "The server's ICE servers could not be read.")
        }
    }
}

extension SystemSummary {
    init(_ f: SovEmuGraphQL.SystemFields) {
        self.init(
            id: f.id, name: f.name, short: f.short, manufacturer: f.manufacturer, year: f.year, color: f.color,
            gameCount: f.gameCount, playable: f.playable, needsGpu: f.needsGpu, rendering: f.rendering?.name,
            biosMissing: f.biosMissing, boxAspect: f.boxAspect, photoUrl: f.photoUrl)
    }
}

extension SaveSlot {
    init(_ f: SovEmuGraphQL.SaveFields) {
        self.init(slot: f.slot, savedAt: f.savedAt, screenshotUrl: f.screenshotUrl)
    }
}

extension Game {
    init(_ f: SovEmuGraphQL.GameFields) {
        self.init(
            id: Int64(f.id), system: f.system, title: f.title, fileTitle: f.fileTitle, tags: f.tags, path: f.path,
            size: f.size, lastPlayedAt: f.lastPlayedAt, playCount: f.playCount, image: f.image, thumb: f.thumb,
            video: f.video, description: f.description, releaseDate: f.releaseDate, developer: f.developer,
            publisher: f.publisher, genre: f.genre, players: f.players, rating: f.rating, discs: f.discs,
            // A kind a newer server adds is drawn as a disc.
            partKind: f.partKind.map { PartKind(rawValue: $0.name) ?? .disc },
            favourite: f.favourite, release: f.release, patch: f.patch,
            autoSave: f.autoSave.map { SaveSlot($0.fragments.saveFields) }, imageSmall: f.imageSmall, cover: f.cover,
            // A rating a newer server adds is no rating.
            esrb: f.esrb.flatMap { EsrbRating(rawValue: $0.name) }, esrbBadgeUrl: f.esrbBadgeUrl,
            modes: f.modes, series: f.series, themes: f.themes, genres: f.genres)
    }
}

extension HomeFeed {
    init(_ d: SovEmuGraphQL.HomeQuery.Data) {
        self.init(
            featured: d.home.featured.map { Game($0.fragments.gameFields) },
            recent: d.home.recent.map { Game($0.fragments.gameFields) },
            added: d.home.added.map { Game($0.fragments.gameFields) },
            topRated: d.home.topRated.map { Game($0.fragments.gameFields) },
            favourites: d.home.favourites.map { Game($0.fragments.gameFields) },
            collections: d.collections.map { c in
                HomeCollection(id: c.id, name: c.name, games: c.games.map { Game($0.fragments.gameFields) })
            })
    }
}

extension GamePatch {
    init(_ p: SovEmuGraphQL.PatchesQuery.Data.Game.Patch) {
        self.init(id: p.id, name: p.name, isDefault: p.isDefault)
    }
}

extension GameDecoration {
    init(_ d: SovEmuGraphQL.GameDecorationQuery.Data.Game.Decoration) {
        self.init(
            url: d.url, width: d.width, height: d.height, top: d.top, left: d.left, bottom: d.bottom, right: d.right)
    }
}

extension Cheat {
    init(_ f: SovEmuGraphQL.CheatFields) {
        self.init(id: f.id, description: f.description, code: f.code, enabled: f.enabled)
    }
}

extension SessionInfo {
    init(_ f: SovEmuGraphQL.SessionFields) {
        self.init(
            id: f.id, gameId: Int64(f.gameId), system: f.system, title: f.title, core: f.core, width: f.width,
            height: f.height, fps: f.fps, connected: f.connected, discs: f.discs, disc: f.disc)
    }
}

extension StartStatus {
    init(_ s: SovEmuGraphQL.StartProgressQuery.Data.StartProgress) {
        // A phase a newer server knows is `unknown`.
        self.init(
            phase: StartPhase(rawValue: s.phase.name) ?? .unknown, read: s.read, total: s.total, elapsedMs: s.elapsedMs,
            phaseMs: s.phaseMs, error: s.error)
    }
}

extension ControllerMapping {
    init(_ f: SovEmuGraphQL.MappingFields) {
        self.init(
            controller: f.controller, system: f.system, name: f.name,
            bindings: f.bindings.map { ControllerBinding(input: $0.input, button: $0.button.name) },
            // A source a newer server adds is still a default, not the user's.
            source: MappingSource(rawValue: f.source.name) ?? .admin)
    }
}

extension PadLayout {
    init(_ f: SovEmuGraphQL.LayoutFields) {
        self.init(
            id: f.id, name: f.name, width: f.width, height: f.height,
            body: f.body.map { PadShape(x: $0.x, y: $0.y, w: $0.w, h: $0.h, r: $0.r, tone: $0.tone) },
            keys: f.keys.map { PadKey(key: $0.key, label: $0.label, x: $0.x, y: $0.y, w: $0.w, h: $0.h, r: $0.r) })
    }
}

extension ControlsInfo {
    init(_ d: SovEmuGraphQL.ControlsQuery.Data) {
        self.init(
            controls: d.system.map { system in
                let c = system.controls
                return SystemControls(
                    buttons: c.buttons.map { SystemButton(button: $0.button.name, label: $0.label) },
                    layout: PadLayout(c.layout.fragments.layoutFields),
                    sticks: c.sticks.map { SystemStick(stick: $0.stick.name, label: $0.label, key: $0.key) })
            },
            controllerLayouts: d.controllerLayouts.map { PadLayout($0.fragments.layoutFields) })
    }
}
