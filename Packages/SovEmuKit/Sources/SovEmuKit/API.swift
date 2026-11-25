import Apollo
import ApolloAPI
import Foundation

// MARK: - Models: what the app reads from the SovEmu GraphQL API.
//
// The operations are `GraphQL/operations.graphql`, generated into `Generated/` by Apollo
// (`scripts/codegen.sh`) and checked there against `GraphQL/schema.graphqls`, a copy of
// SovEmu's `SovEmu.Backend/SovEmu.Server/schema.graphql`. The generated types stay internal;
// `GraphQLMapping.swift` turns them into these.

public struct User: Codable, Sendable, Equatable {
    public let id: Int64
    public let username: String
    /// The same as `role == .admin`.
    public let isAdmin: Bool
    public let role: Role

    public init(id: Int64, username: String, isAdmin: Bool, role: Role) {
        (self.id, self.username, self.isAdmin, self.role) = (id, username, isAdmin, role)
    }

}

/// What a user may do (`Role`).
public enum Role: String, Codable, Sendable {
    case viewer = "VIEWER"
    case admin = "ADMIN"
}

/// `Viewer`: who is signed in, and whether first-run setup is needed.
public struct AuthStatus: Codable, Sendable {
    public let setupRequired: Bool
    public let user: User?
}

/// `BootstrapConfig`: how to sign in at this address. Anonymous, and the first thing the app
/// asks a server (so also the check that there is a SovEmu server at an address).
public struct BootstrapConfig: Codable, Sendable, Equatable {
    /// False when this address is not one of the server's `SOVEMU_PUBLIC_URL`; the rest is nil.
    public let signInAvailable: Bool
    /// The address the request reached, as the server saw it.
    public let address: String
    public let issuer: String?
    public let webClientId: String?
    /// The client the app signs in as, with a code or a password.
    public let deviceClientId: String?
    public let authorizationEndpoint: String?
    public let tokenEndpoint: String?
    public let revocationEndpoint: String?
    public let deviceAuthorizationEndpoint: String?
    public let verificationUri: String?
    /// Nil when the server has turned password sign-in off.
    public let passwordEndpoint: String?
    /// The mobile client: what the app signs in as through the system browser.
    public let mobileClientId: String?
    /// Where the browser's sign-in comes back to, the app's own scheme.
    public let mobileRedirectUri: String?

    public init(
        signInAvailable: Bool, address: String, issuer: String? = nil, webClientId: String? = nil,
        deviceClientId: String? = nil, authorizationEndpoint: String? = nil, tokenEndpoint: String? = nil,
        revocationEndpoint: String? = nil, deviceAuthorizationEndpoint: String? = nil, verificationUri: String? = nil,
        passwordEndpoint: String? = nil, mobileClientId: String? = nil, mobileRedirectUri: String? = nil
    ) {
        self.mobileClientId = mobileClientId
        self.mobileRedirectUri = mobileRedirectUri
        self.signInAvailable = signInAvailable
        self.address = address
        self.issuer = issuer
        self.webClientId = webClientId
        self.deviceClientId = deviceClientId
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.deviceAuthorizationEndpoint = deviceAuthorizationEndpoint
        self.verificationUri = verificationUri
        self.passwordEndpoint = passwordEndpoint
    }


    static let codeOnlyMessage = "This server signs in only with a code shown on the screen."

    /// Why this app cannot sign in here, for people; nil when it can (with a code, a password,
    /// or both).
    public var signInProblem: String? {
        guard signInAvailable, let endpoints = endpoints(relativeTo: nil) else {
            return "Signing in isn't available at \(address). Add it to SOVEMU_PUBLIC_URL on the server."
        }
        if endpoints.password == nil && endpoints.deviceAuthorization == nil { return "The server sent no sign-in details." }
        return nil
    }

    /// Whether the app can sign in with a code approved on another screen.
    public var canPair: Bool { signInAvailable && deviceAuthorizationEndpoint != nil }

    /// Whether the app can sign in with a username and password.
    public var canUsePassword: Bool { signInAvailable && passwordEndpoint != nil }

    /// Whether the app can sign in through the system browser (the server's own page).
    public var canUseBrowser: Bool {
        signInAvailable && authorizationEndpoint != nil && mobileClientId != nil && mobileRedirectUri != nil
    }

    /// The client's endpoints, resolved against the server address when relative; nil when
    /// nothing can sign in here.
    public func endpoints(relativeTo base: URL?) -> SignInEndpoints? {
        func url(_ string: String?) -> URL? { string.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL } }
        guard signInAvailable, let clientId = deviceClientId, let token = url(tokenEndpoint) else { return nil }
        return SignInEndpoints(
            clientId: clientId, token: token, revocation: url(revocationEndpoint), password: url(passwordEndpoint),
            deviceAuthorization: url(deviceAuthorizationEndpoint), authorization: url(authorizationEndpoint),
            mobileClientId: mobileClientId, mobileRedirectURI: mobileRedirectUri)
    }
}

public struct SystemSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let short: String
    public let manufacturer: String
    public let year: Int
    public let color: String
    public let gameCount: Int
    public let playable: Bool
    /// A 3D system: renders with OpenGL and reads analog sticks.
    public let needsGpu: Bool
    /// For a 3D system: `GPU`, `SOFTWARE` (slow) or `OFF`.
    public let rendering: String?
    /// A BIOS file it cannot start games without is missing.
    public let biosMissing: Bool
    /// The shape of its games' boxes, width over height (SNES landscape, NES portrait): its game
    /// cards take it, so box art fills them.
    public let boxAspect: Double


    public init(
        id: String, name: String, short: String, manufacturer: String = "", year: Int = 0, color: String = "#4169e1",
        gameCount: Int = 0, playable: Bool = true, needsGpu: Bool = false, rendering: String? = nil, biosMissing: Bool = false,
        boxAspect: Double = defaultBoxAspect
    ) {
        self.boxAspect = boxAspect
        (self.id, self.name, self.short, self.manufacturer, self.year, self.color) = (id, name, short, manufacturer, year, color)
        (self.gameCount, self.playable, self.needsGpu, self.rendering, self.biosMissing) =
            (gameCount, playable, needsGpu, rendering, biosMissing)
    }

    /// The accent colour as (red, green, blue) in 0...1.
    public var rgb: (Double, Double, Double) {
        let value = Int(color.dropFirst(), radix: 16) ?? 0x4169e1
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
}

/// `GameSession`: a running game.
public struct SessionInfo: Codable, Sendable {
    public let id: String
    public let gameId: Int64
    public let system: String
    public let title: String
    public let core: String
    public let width: Int
    public let height: Int
    public let fps: Double
    /// A client is streaming it.
    public let connected: Bool
    /// How many discs the game has (1 for most), and which is in the tray (from 1).
    public let discs: Int?
    public let disc: Int?

}

public struct IceServer: Codable, Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?

    enum CodingKeys: String, CodingKey { case urls, username, credential }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `urls` may be one string or a list, as in `RTCIceServer`.
        if let one = try? c.decode(String.self, forKey: .urls) {
            urls = [one]
        } else {
            urls = try c.decode([String].self, forKey: .urls)
        }
        username = try c.decodeIfPresent(String.self, forKey: .username)
        credential = try c.decodeIfPresent(String.self, forKey: .credential)
    }
}

/// One input driving one RetroPad button: the schema's `Binding` (and `BindingInput`).
public struct ControllerBinding: Codable, Sendable, Equatable {
    /// A controller input (`south`, `l1`, `up` …) or a keyboard's `KeyboardEvent.code`.
    public let input: String
    /// A `PadButton`: `B`, `SELECT`, `L2` …
    public let button: String

    public init(input: String, button: String) {
        self.input = input
        self.button = button
    }

}

/// Where a mapping in force comes from (`MappingSource`).
public enum MappingSource: String, Codable, Sendable {
    /// The user's own.
    case user = "USER"
    /// An admin's default, set on the admin page.
    case admin = "ADMIN"
    /// A default from the server's environment (`SOVEMU_CONTROLLERS__<n>__…`).
    case environment = "ENVIRONMENT"

    /// A server default rather than the user's own.
    public var isDefault: Bool { self != .user }
}

/// The mapping in force for one controller model, on one system or on every system: the
/// user's own, else the server's default.
public struct ControllerMapping: Codable, Sendable, Equatable {
    /// `keyboard`, a known model (`xbox`, `dualsense` …) or `pad:name:<slug>`.
    public let controller: String
    /// The system it is for, or nil for every system.
    public let system: String?
    public let name: String
    public let bindings: [ControllerBinding]
    public let source: MappingSource

    public init(controller: String, system: String? = nil, name: String, bindings: [ControllerBinding], source: MappingSource) {
        self.controller = controller
        self.system = system
        self.name = name
        self.bindings = bindings
        self.source = source
    }

}

// MARK: - Controls and diagrams (`System.controls`, `controllerLayouts`)

/// A rounded rectangle on a diagram; a circle when `r` is half its width and height.
public struct PadShape: Codable, Sendable, Equatable {
    public let x: Double, y: Double, w: Double, h: Double, r: Double
    /// 0 the body, 1 a recess drawn darker (a screen, a stick's well).
    public let tone: Int

    public init(x: Double, y: Double, w: Double, h: Double, r: Double, tone: Int = 0) {
        (self.x, self.y, self.w, self.h, self.r, self.tone) = (x, y, w, h, r, tone)
    }
}

/// A button on a diagram.
public struct PadKey: Codable, Sendable, Equatable {
    /// A RetroPad button (`B`, `START` …) on a system's pad, an input name (`south` …) on a
    /// controller's.
    public let key: String
    /// What the pad prints on it.
    public let label: String
    public let x: Double, y: Double, w: Double, h: Double, r: Double

    public init(key: String, label: String, x: Double, y: Double, w: Double, h: Double, r: Double) {
        (self.key, self.label, self.x, self.y, self.w, self.h, self.r) = (key, label, x, y, w, h, r)
    }
}

/// A pad, drawn from shapes on a `width`×`height` canvas (160×100).
public struct PadLayout: Codable, Sendable, Equatable {
    /// A system id, or a controller family (`xbox`, `playstation`, `nintendo`, `generic`).
    public let id: String
    public let name: String
    public let width: Double
    public let height: Double
    public let body: [PadShape]
    public let keys: [PadKey]

    public init(id: String, name: String, width: Double = 160, height: Double = 100, body: [PadShape], keys: [PadKey]) {
        (self.id, self.name, self.width, self.height, self.body, self.keys) = (id, name, width, height, body, keys)
    }


    /// The part of the canvas worth drawing: the bounding box of every shape and key, 3 units
    /// wider all round, within the canvas (as the web client crops), so a flat pad does not
    /// float in empty space. The whole canvas when nothing is drawn.
    public var visibleBounds: (x: Double, y: Double, w: Double, h: Double) {
        let rects = body.map { ($0.x, $0.y, $0.w, $0.h) } + keys.map { ($0.x, $0.y, $0.w, $0.h) }
        guard !rects.isEmpty else { return (0, 0, width, height) }
        let pad = 3.0
        let x0 = max(0, rects.map(\.0).min()! - pad)
        let y0 = max(0, rects.map(\.1).min()! - pad)
        let x1 = min(width, rects.map { $0.0 + $0.2 }.max()! + pad)
        let y1 = min(height, rects.map { $0.1 + $0.3 }.max()! + pad)
        return (x0, y0, x1 - x0, y1 - y0)
    }
}

/// One of a system's buttons: the RetroPad button that drives it and what the console calls it.
public struct SystemButton: Codable, Sendable, Equatable {
    /// A `PadButton`: `B`, `START` …
    public let button: String
    public let label: String

    public init(button: String, label: String) {
        self.button = button
        self.label = label
    }

    public var retroButton: RetroButton? { RetroButton(name: button) }
}

/// One of a system's analog controls: the player's stick that drives it, what the console calls
/// it, and the key on the system's diagram it lights. Sticks are not remapped (docs/CONTROLLERS.md).
public struct SystemStick: Codable, Sendable, Equatable {
    /// A `Stick`: `LEFT` or `RIGHT`.
    public let stick: String
    public let label: String
    public let key: String

    public init(stick: String, label: String, key: String) {
        self.stick = stick
        self.label = label
        self.key = key
    }

    public var isRight: Bool { stick == "RIGHT" }
    /// The player's stick that drives it, as a row shows it.
    public var stickName: String { isRight ? "Right stick" : "Left stick" }
    /// The stick on a controller's diagram.
    public var controllerKey: String { isRight ? "r3" : "l3" }
}

/// A system's buttons, in the order to list them, its analog controls, and its pad's diagram.
public struct SystemControls: Codable, Sendable, Equatable {
    public let buttons: [SystemButton]
    public let sticks: [SystemStick]
    public let layout: PadLayout

    public init(buttons: [SystemButton], layout: PadLayout, sticks: [SystemStick] = []) {
        self.buttons = buttons
        self.layout = layout
        self.sticks = sticks
    }
}

/// What the remap screen draws: the system's controls (nil for an unknown system) and the
/// controllers' diagrams by family.
public struct ControlsInfo: Sendable, Equatable {
    public let controls: SystemControls?
    public let controllerLayouts: [PadLayout]

    public init(controls: SystemControls?, controllerLayouts: [PadLayout]) {
        self.controls = controls
        self.controllerLayouts = controllerLayouts
    }

    /// The diagram for a controller family, else the generic one.
    public func layout(for family: ControllerFamily) -> PadLayout? {
        controllerLayouts.first { $0.id == family.rawValue } ?? controllerLayouts.first { $0.id == ControllerFamily.generic.rawValue }
    }
}

public struct ClientConfig: Codable, Sendable {
    /// The `JSON` scalar `iceServers`: an array of `RTCIceServer` objects.
    public let iceServers: [IceServer]
}

/// A failed call: a GraphQL error (`code` is its `extensions.code`, such as `UNAUTHENTICATED`
/// or `NOT_FOUND`), or an HTTP failure (`status`, with no code).
public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let message: String
    public var errorDescription: String? { message }

    /// Not signed in (or the session expired): sign in again.
    public var isUnauthenticated: Bool { code == "UNAUTHENTICATED" || status == 401 }

    public init(status: Int, code: String? = nil, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }
}

// MARK: - Client

/// Calls to the SovEmu GraphQL API, through Apollo. Each request carries `Authorization: Bearer`
/// with an access token from `auth` (none when signed out); an `UNAUTHENTICATED` answer refreshes
/// the token and retries once (`BearerInterceptor`). No cookies are sent or kept.
///
/// Every failure is an `APIError` (a GraphQL error with its `extensions.code`, or an HTTP one with
/// its status), except a request that never reached the server (`URLError`) and cancellation.
public final class SovEmuAPI: Sendable {
    public let baseURL: URL
    /// Signs in and out and keeps the access token; nil for an API that is never signed in.
    public let auth: TokenClient?
    /// Sends the access token.
    private let client: ApolloClient
    /// Sends none: `bootstrapConfig` is asked before the client knows where to sign in.
    private let anonymous: ApolloClient

    public init(baseURL: URL, auth: TokenClient? = nil, session: URLSession = SovEmuAPI.makeSession()) {
        self.baseURL = baseURL
        self.auth = auth
        client = GraphQLClient.make(baseURL: baseURL, auth: auth, session: session)
        anonymous = GraphQLClient.make(baseURL: baseURL, auth: nil, session: session)
    }

    /// A session that neither sends nor stores cookies: the API authenticates with tokens.
    public static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return configuration
    }

    public static func makeSession() -> URLSession { URLSession(configuration: sessionConfiguration()) }

    /// The cookie the server's sign-in used before tokens: it means nothing now, so it goes.
    public static let legacySessionCookie = "sovemu_session"

    /// Deletes any stored `sovemu_session` cookie (from an older version of the app).
    public static func clearLegacySessionCookie(in storage: HTTPCookieStorage = .shared) {
        for cookie in storage.cookies ?? [] where cookie.name == legacySessionCookie {
            storage.deleteCookie(cookie)
        }
    }

    /// A refresh token is stored.
    public var isSignedIn: Bool { auth?.isSignedIn ?? false }

    /// Signs in with the password grant; throws `AuthError` with the server's description.
    public func signIn(username: String, password: String) async throws {
        guard let auth else { throw AuthError.signedOut }
        try await auth.signIn(username: username, password: password)
    }

    /// A code to show, to sign in by approving it on another screen (after `bootstrap`).
    public func requestDeviceCode() async throws -> DeviceCode {
        guard let auth else { throw AuthError.signedOut }
        return try await auth.requestDeviceCode()
    }

    /// Signs a TV in as this account: the code its screen shows (*Sign in a TV*). Throws
    /// `APIError` (`NOT_FOUND`: no TV is waiting with that code).
    public func approveDeviceCode(_ code: String) async throws {
        _ = try await perform(SovEmuGraphQL.ApproveDeviceCodeMutation(code: code))
    }

    /// A browser sign-in to open (the server's own page), or nil when the server offers none.
    public func browserSignIn() async -> BrowserSignInRequest? {
        await auth?.browserSignInRequest()
    }

    /// Finishes a browser sign-in with the URL the browser came back with: signed in, or an
    /// `AuthError` saying why.
    public func finishBrowserSignIn(_ callback: URL, request: BrowserSignInRequest) async throws {
        guard let auth else { throw AuthError.signedOut }
        try await auth.finishBrowserSignIn(callback, request: request)
    }

    /// One poll for `code`'s approval; `.approved` means signed in.
    public func pollDeviceCode(_ code: DeviceCode) async throws -> DevicePoll {
        guard let auth else { return .refused(.failed) }
        return try await auth.pollDeviceCode(code)
    }

    /// Revokes the sign-in and forgets the tokens (also when the server cannot be reached).
    public func signOut() async { await auth?.signOut() }

    // MARK: Sending

    /// Runs one query and returns its data, or throws its first error.
    private func fetch<Query: GraphQLQuery>(_ query: Query, signedIn: Bool = true) async throws -> Query.Data
    where Query.ResponseFormat == SingleResponseFormat {
        let client = signedIn ? client : anonymous
        return try await Self.answer { try await client.fetch(query: query, cachePolicy: .networkOnly) }
    }

    /// Runs one mutation and returns its data, or throws its first error.
    private func perform<Mutation: GraphQLMutation>(_ mutation: Mutation) async throws -> Mutation.Data
    where Mutation.ResponseFormat == SingleResponseFormat {
        try await Self.answer { try await client.perform(mutation: mutation) }
    }

    /// Folds what can go wrong with one operation into `APIError`: an HTTP failure, an answer that
    /// does not fit the schema, a GraphQL error, no data. A request that never reached the server
    /// (`URLError`), a sign-in failure other than a refusal, and cancellation pass through.
    static func answer<Operation: GraphQLOperation>(
        _ send: () async throws -> GraphQLResponse<Operation>
    ) async throws -> Operation.Data {
        let response: GraphQLResponse<Operation>
        do {
            response = try await send()
        } catch let error as ResponseCodeInterceptor.ResponseCodeError {
            throw APIError(error)
        } catch let error where error is APIError || error is URLError || error is AuthError
            || error is CancellationError
        {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw APIError(status: 200, message: "The server's answer could not be read.")
        }
        if let first = response.errors?.first { throw APIError(first) }
        guard let data = response.data else { throw APIError(status: 200, message: "The server's answer had no data.") }
        return data
    }

    // MARK: Operations

    /// How to sign in here (asked without a token, so it works before sign-in and before the
    /// client knows where to refresh). Hands the endpoints to `auth`.
    public func bootstrap() async throws -> BootstrapConfig {
        let config = BootstrapConfig(try await fetch(SovEmuGraphQL.BootstrapQuery(), signedIn: false).bootstrapConfig)
        await auth?.setEndpoints(config.endpoints(relativeTo: baseURL))
        return config
    }

    public func status() async throws -> AuthStatus {
        AuthStatus(try await fetch(SovEmuGraphQL.ViewerQuery()).viewer)
    }
    public func config() async throws -> ClientConfig {
        try ClientConfig(try await fetch(SovEmuGraphQL.ClientConfigQuery()).clientConfig)
    }
    public func systems() async throws -> [SystemSummary] {
        try await fetch(SovEmuGraphQL.SystemsQuery()).systems.map { SystemSummary($0.fragments.systemFields) }
    }
    public func games(system: String) async throws -> [Game] {
        guard let found = try await fetch(SovEmuGraphQL.SystemGamesQuery(id: system)).system else {
            throw APIError(status: 200, code: "NOT_FOUND", message: "No such system.")
        }
        return found.games.map { Game($0.fragments.gameFields) }
    }
    /// Starts a game, named `startId` so its progress can be followed (`startProgress`).
    public func startSession(gameId: Int64, startId: String? = nil) async throws -> SessionInfo {
        let start = SovEmuGraphQL.StartSessionMutation(gameId: int32(gameId), startId: .orNull(startId))
        let data = try await perform(start)
        return SessionInfo(data.startSession.fragments.sessionFields)
    }
    /// How far the start named `startId` has got.
    public func startProgress(startId: String) async throws -> StartStatus {
        StartStatus(try await fetch(SovEmuGraphQL.StartProgressQuery(startId: startId)).startProgress)
    }

    /// The home screen's rows, and a row per collection.
    public func home() async throws -> HomeFeed {
        HomeFeed(try await fetch(SovEmuGraphQL.HomeQuery()))
    }
    /// Games on every system matching `text` (the server's first 48).
    public func search(_ text: String) async throws -> [Game] {
        try await fetch(SovEmuGraphQL.SearchQuery(text: text)).search.map { Game($0.fragments.gameFields) }
    }

    /// A game, or `NOT_FOUND`.
    private func game<T>(_ game: T?) throws -> T {
        guard let game else { throw APIError(status: 200, code: "NOT_FOUND", message: "No such game.") }
        return game
    }

    public func patches(gameId: Int64) async throws -> [GamePatch] {
        try game(try await fetch(SovEmuGraphQL.PatchesQuery(id: int32(gameId))).game)
            .patches.map(GamePatch.init)
    }
    /// Plays a game with a patch (nil: the original) from now on.
    public func setPatch(gameId: Int64, patchId: Int?) async throws {
        _ = try await perform(
            SovEmuGraphQL.SetPatchMutation(gameId: int32(gameId), patchId: .orNull(patchId.map { int32($0) })))
    }
    /// The artwork to frame a game's picture with; nil when there is none.
    public func decoration(gameId: Int64) async throws -> GameDecoration? {
        try game(try await fetch(SovEmuGraphQL.GameDecorationQuery(id: int32(gameId))).game)
            .decoration.map(GameDecoration.init)
    }
    /// This user's saves of a game.
    public func saves(gameId: Int64) async throws -> [SaveSlot] {
        try game(try await fetch(SovEmuGraphQL.SavesQuery(id: int32(gameId))).game)
            .saves.map { SaveSlot($0.fragments.saveFields) }
    }

    public func setFavourite(gameId: Int64, favourite: Bool) async throws {
        _ = try await perform(SovEmuGraphQL.SetFavouriteMutation(gameId: int32(gameId), favourite: favourite))
    }
    /// This user's collections, each saying whether the game is in it, by name.
    public func collectionChoices(gameId: Int64) async throws -> [CollectionChoice] {
        let data = try await fetch(SovEmuGraphQL.CollectionChoicesQuery(id: int32(gameId)))
        let member = Set(try game(data.game).collectionIds)
        return data.collections.map { CollectionChoice(id: $0.id, name: $0.name, member: member.contains($0.id)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Makes a collection (its name trimmed to 64 characters); returns its id.
    public func createCollection(name: String) async throws -> Int {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        return try await perform(SovEmuGraphQL.CreateCollectionMutation(name: trimmed)).createCollection.id
    }
    public func setInCollection(collectionId: Int, gameId: Int64, member: Bool) async throws {
        let set = SovEmuGraphQL.SetInCollectionMutation(
            collectionId: int32(collectionId), gameId: int32(gameId), member: member)
        _ = try await perform(set)
    }

    /// This user's cheats for a game.
    public func cheats(gameId: Int64) async throws -> [Cheat] {
        try game(try await fetch(SovEmuGraphQL.CheatsQuery(id: int32(gameId))).game)
            .cheats.map { Cheat($0.fragments.cheatFields) }
    }
    /// Adds a cheat; returns the game's cheats after it.
    public func addCheat(gameId: Int64, code: String, description: String) async throws -> [Cheat] {
        try await perform(SovEmuGraphQL.AddCheatMutation(gameId: int32(gameId), code: code, description: description))
            .addCheat.map { Cheat($0.fragments.cheatFields) }
    }
    /// Turns a cheat on or off (a running session applies it at once); returns the game's cheats.
    public func setCheatEnabled(gameId: Int64, cheatId: Int, enabled: Bool) async throws -> [Cheat] {
        try await perform(
            SovEmuGraphQL.SetCheatEnabledMutation(gameId: int32(gameId), cheatId: int32(cheatId), enabled: enabled))
            .setCheatEnabled.map { Cheat($0.fragments.cheatFields) }
    }
    public func deleteCheat(gameId: Int64, cheatId: Int) async throws {
        _ = try await perform(SovEmuGraphQL.DeleteCheatMutation(gameId: int32(gameId), cheatId: int32(cheatId)))
    }

    /// A `/media/…` path the API handed out, as a full URL on this server (an absolute one as it is).
    public func media(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
    /// Sends the complete WebRTC offer SDP, naming the client (`ios 0.1.0 (iPad, iPadOS 18.1)`,
    /// shown on the admin's sessions page); returns the worker's answer SDP.
    public func offer(sessionId: String, sdp: String, client: String? = nil) async throws -> String {
        try await perform(Self.offer(sessionId: sessionId, sdp: sdp, client: client)).sessionOffer
    }

    static func offer(sessionId: String, sdp: String, client: String?) -> SovEmuGraphQL.SessionOfferMutation {
        SovEmuGraphQL.SessionOfferMutation(id: sessionId, sdp: sdp, client: .orNull(client))
    }
    /// Names this sign-in's device on the server ("SovEmu for iOS 0.1.0 · iPad"), for the
    /// admin's Devices page.
    public func nameDevice(_ name: String) async throws {
        _ = try await perform(SovEmuGraphQL.NameDeviceMutation(name: name))
    }
    public func stopSession(_ id: String) async throws {
        _ = try await perform(SovEmuGraphQL.StopSessionMutation(id: id))
    }
    /// Changes a multi-disc game's disc (from 1).
    public func setDisc(sessionId: String, disc: Int) async throws {
        _ = try await perform(SovEmuGraphQL.SetDiscMutation(sessionId: sessionId, disc: int32(disc)))
    }

    public func saveState(sessionId: String, slot: Int) async throws {
        _ = try await perform(SovEmuGraphQL.SaveStateMutation(sessionId: sessionId, slot: int32(slot)))
    }
    public func loadState(sessionId: String, slot: Int) async throws {
        _ = try await perform(SovEmuGraphQL.LoadStateMutation(sessionId: sessionId, slot: int32(slot)))
    }

    /// Sends what went wrong on this device to the server's log (`client event`); returns how
    /// many it logged. Callers drop a failure: a report must not get in the player's way.
    @discardableResult
    public func reportClientEvents(client: String, events: [ClientEvent]) async throws -> Int {
        guard isSignedIn, !events.isEmpty else { return 0 }
        return try await perform(Self.report(client: client, events: events)).reportClientEvents
    }

    static func report(client: String, events: [ClientEvent]) -> SovEmuGraphQL.ReportClientEventsMutation {
        SovEmuGraphQL.ReportClientEventsMutation(client: client, events: events.map {
            SovEmuGraphQL.ClientEventInput(
                kind: .init(rawValue: $0.kind.rawValue), message: $0.message, sessionId: .orNull($0.sessionId),
                at: .some($0.at))
        })
    }

    /// The mappings in force for this user on a system (nil: on every system), one per model:
    /// their own for the system, their own for every system, the default for the system, the
    /// default for every system. A model missing from the list uses the built-in defaults.
    public func controllerMappings(system: String?) async throws -> [ControllerMapping] {
        try await fetch(SovEmuGraphQL.ControllerMappingsQuery(system: .orNull(system)))
            .controllerMappings.map { ControllerMapping($0.fragments.mappingFields) }
    }
    /// Saves a controller model's mapping for a system (nil: every system).
    @discardableResult
    public func saveControllerMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding]) async throws
        -> ControllerMapping
    {
        let save = Self.saveMapping(controller: controller, system: system, name: name, bindings: bindings)
        let data = try await perform(save)
        return ControllerMapping(data.saveControllerMapping.fragments.mappingFields)
    }

    static func saveMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding])
        -> SovEmuGraphQL.SaveControllerMappingMutation
    {
        SovEmuGraphQL.SaveControllerMappingMutation(
            controller: controller, system: .orNull(system), name: name,
            bindings: bindings.map { SovEmuGraphQL.BindingInput(input: $0.input, button: .init(rawValue: $0.button)) })
    }
    /// Removes the user's own mapping for a model on a system (nil: every system); returns
    /// whether it had one. What then applies comes from `controllerMappings` again.
    @discardableResult
    public func resetControllerMapping(controller: String, system: String?) async throws -> Bool {
        try await perform(SovEmuGraphQL.ResetControllerMappingMutation(controller: controller, system: .orNull(system)))
            .resetControllerMapping
    }
    /// A system's buttons and pad, and the controllers' diagrams.
    public func controls(system: String) async throws -> ControlsInfo {
        ControlsInfo(try await fetch(SovEmuGraphQL.ControlsQuery(id: system)))
    }
}

/// The mapping calls `Mappings` needs (`SovEmuAPI`, or a stand-in in tests).
public protocol ControllerMappingService: Sendable {
    func controllerMappings(system: String?) async throws -> [ControllerMapping]
    func saveControllerMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding]) async throws
        -> ControllerMapping
    func resetControllerMapping(controller: String, system: String?) async throws -> Bool
}

extension SovEmuAPI: ControllerMappingService {}

/// A number as a GraphQL `Int` argument, which is 32-bit (Apollo types it `Int32`). An id out
/// of its range names nothing, and the server says so (`NOT_FOUND`), rather than the app trapping.
func int32(_ value: some BinaryInteger) -> Int32 { Int32(clamping: value) }
