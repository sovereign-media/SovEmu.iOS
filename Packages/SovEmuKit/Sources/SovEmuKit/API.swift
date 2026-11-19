import Foundation

// MARK: - Models: the shapes of the SovEmu GraphQL API (`SovEmu.Server/schema.graphql`).

public struct User: Codable, Sendable, Equatable {
    public let id: Int64
    public let username: String
    public let isAdmin: Bool

    static let fields = "id username isAdmin"
}

/// `Viewer`: who is signed in, and whether first-run setup is needed.
public struct AuthStatus: Codable, Sendable {
    public let setupRequired: Bool
    public let user: User?
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

    static let fields = "id name short manufacturer year color gameCount playable needsGpu rendering"

    /// The accent colour as (red, green, blue) in 0...1.
    public var rgb: (Double, Double, Double) {
        let value = Int(color.dropFirst(), radix: 16) ?? 0x4169e1
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
}

public struct Game: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let system: String
    public let title: String
    /// No-Intro tags from the file name: "USA", "Rev 1" …
    public let tags: [String]
    /// Bytes (a GraphQL `Float`).
    public let size: Double
    public let lastPlayedAt: String?
    public let playCount: Int

    static let fields = "id system title tags size lastPlayedAt playCount"
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

    static let fields = "id gameId system title core width height fps connected discs disc"
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

    static let fields = "input button"
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

    public init(from decoder: Decoder) throws {
        // A source a newer server adds is still a default, not the user's.
        self = MappingSource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .admin
    }
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

    static let fields = "controller system name bindings { \(ControllerBinding.fields) } source"
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

    static let fields = "id name width height body { x y w h r tone } keys { key label x y w h r }"

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

/// A system's buttons, in the order to list them, and its pad's diagram.
public struct SystemControls: Codable, Sendable, Equatable {
    public let buttons: [SystemButton]
    public let layout: PadLayout

    public init(buttons: [SystemButton], layout: PadLayout) {
        self.buttons = buttons
        self.layout = layout
    }
}

/// What the remap screen draws: the system's controls (nil for an unknown system) and the
/// controllers' diagrams by family.
public struct ControlsInfo: Decodable, Sendable, Equatable {
    public let controls: SystemControls?
    public let controllerLayouts: [PadLayout]

    public init(controls: SystemControls?, controllerLayouts: [PadLayout]) {
        self.controls = controls
        self.controllerLayouts = controllerLayouts
    }

    enum CodingKeys: String, CodingKey { case system, controllerLayouts }
    struct SystemField: Decodable { let controls: SystemControls }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        controls = try c.decodeIfPresent(SystemField.self, forKey: .system)?.controls
        controllerLayouts = try c.decode([PadLayout].self, forKey: .controllerLayouts)
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

// MARK: - GraphQL wire format

/// A GraphQL variable value. Only the kinds the app sends.
public enum GraphQLValue: Encodable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case list([GraphQLValue])
    case object([String: GraphQLValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .list(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// The body of `POST /graphql`.
struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLValue]
}

/// The body of every `/graphql` answer (HTTP 200 even when it failed).
struct GraphQLResponse<T: Decodable>: Decodable {
    struct Failure: Decodable {
        struct Extensions: Decodable { let code: String? }
        let message: String
        let extensions: Extensions?
    }
    let data: T?
    let errors: [Failure]?
}

// MARK: - Documents

/// The query documents the app sends, written by hand against `schema.graphql`.
enum Documents {
    static let viewer = "query Viewer { viewer { setupRequired user { \(User.fields) } } }"
    static let login = """
        mutation Login($username: String!, $password: String!) { \
        login(username: $username, password: $password) { \(User.fields) } }
        """
    static let logout = "mutation Logout { logout }"
    static let clientConfig = "query ClientConfig { clientConfig { iceServers } }"
    static let systems = "query Systems { systems { \(SystemSummary.fields) } }"
    static let games = "query Games($system: ID!) { system(id: $system) { games { \(Game.fields) } } }"
    static let startSession = """
        mutation StartSession($gameId: Int!) { startSession(gameId: $gameId) { \(SessionInfo.fields) } }
        """
    static let sessionOffer = "mutation SessionOffer($id: ID!, $sdp: String!) { sessionOffer(id: $id, sdp: $sdp) }"
    static let stopSession = "mutation StopSession($id: ID!) { stopSession(id: $id) }"
    static let setDisc = "mutation SetDisc($sessionId: ID!, $disc: Int!) { setDisc(sessionId: $sessionId, disc: $disc) }"
    static let saveState = "mutation SaveState($sessionId: ID!, $slot: Int!) { saveState(sessionId: $sessionId, slot: $slot) }"
    static let loadState = "mutation LoadState($sessionId: ID!, $slot: Int!) { loadState(sessionId: $sessionId, slot: $slot) }"
    static let controllerMappings = """
        query ControllerMappings($system: ID) { controllerMappings(system: $system) { \(ControllerMapping.fields) } }
        """
    static let saveControllerMapping = """
        mutation SaveControllerMapping($controller: String!, $system: ID, $name: String!, $bindings: [BindingInput!]!) { \
        saveControllerMapping(controller: $controller, system: $system, name: $name, bindings: $bindings) { \(ControllerMapping.fields) } }
        """
    static let resetControllerMapping = """
        mutation ResetControllerMapping($controller: String!, $system: ID) { \
        resetControllerMapping(controller: $controller, system: $system) }
        """
    static let controls = """
        query Controls($system: ID!) { system(id: $system) { controls { buttons { button label } \
        layout { \(PadLayout.fields) } } } controllerLayouts { \(PadLayout.fields) } }
        """
}

// MARK: - Client

/// Calls to the SovEmu GraphQL API. The session cookie (set by `login`, cleared by `logout`)
/// lives in `HTTPCookieStorage.shared`, so sign-in survives relaunches.
public final class SovEmuAPI: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The request for one GraphQL operation.
    static func request(baseURL: URL, query: String, variables: [String: GraphQLValue]) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        return request
    }

    /// Decodes an answer's `data.<field>`, or throws its first error.
    static func decode<T: Decodable>(_ type: T.Type, field: String, from data: Data, status: Int) throws -> T {
        guard let response = try? JSONDecoder().decode(GraphQLResponse<[String: T]>.self, from: data) else {
            if !(200..<300).contains(status) {
                throw APIError(status: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
            }
            // Well-formed errors but data that does not fit `T` (it is null when a field failed).
            if let failure = try? JSONDecoder().decode(GraphQLResponse<JSONNull>.self, from: data).errors?.first {
                throw APIError(status: status, code: failure.extensions?.code, message: failure.message)
            }
            throw APIError(status: status, message: "The server's answer could not be read.")
        }
        if let failure = response.errors?.first {
            throw APIError(status: status, code: failure.extensions?.code, message: failure.message)
        }
        guard let value = response.data?[field] else {
            throw APIError(status: status, message: "The server's answer had no \(field).")
        }
        return value
    }

    /// Decodes an answer's whole `data`, or throws its first error.
    static func decodeData<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        let response: GraphQLResponse<T>
        do {
            response = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
        } catch {
            if !(200..<300).contains(status) {
                throw APIError(status: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
            }
            if let failure = try? JSONDecoder().decode(GraphQLResponse<JSONNull>.self, from: data).errors?.first {
                throw APIError(status: status, code: failure.extensions?.code, message: failure.message)
            }
            throw APIError(status: status, message: "The server's answer could not be read.")
        }
        if let failure = response.errors?.first {
            throw APIError(status: status, code: failure.extensions?.code, message: failure.message)
        }
        guard let value = response.data else { throw APIError(status: status, message: "The server's answer had no data.") }
        return value
    }

    /// Sends one operation and returns its root `field`.
    private func post<T: Decodable>(
        _ query: String, _ variables: [String: GraphQLValue] = [:], field: String, as type: T.Type = T.self
    ) async throws -> T {
        let request = try Self.request(baseURL: baseURL, query: query, variables: variables)
        let (data, response) = try await session.data(for: request)
        return try Self.decode(T.self, field: field, from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func status() async throws -> AuthStatus { try await post(Documents.viewer, field: "viewer") }
    public func login(username: String, password: String) async throws -> User {
        try await post(Documents.login, ["username": .string(username), "password": .string(password)], field: "login")
    }
    public func logout() async throws { _ = try await post(Documents.logout, field: "logout", as: Bool.self) }
    public func config() async throws -> ClientConfig { try await post(Documents.clientConfig, field: "clientConfig") }
    public func systems() async throws -> [SystemSummary] { try await post(Documents.systems, field: "systems") }
    public func games(system: String) async throws -> [Game] {
        struct Games: Decodable { let games: [Game] }
        let found: Games? = try await post(Documents.games, ["system": .string(system)], field: "system")
        guard let found else { throw APIError(status: 200, code: "NOT_FOUND", message: "No such system.") }
        return found.games
    }
    public func startSession(gameId: Int64) async throws -> SessionInfo {
        try await post(Documents.startSession, ["gameId": .int(Int(gameId))], field: "startSession")
    }
    /// Sends the complete WebRTC offer SDP; returns the worker's answer SDP.
    public func offer(sessionId: String, sdp: String) async throws -> String {
        try await post(Documents.sessionOffer, ["id": .string(sessionId), "sdp": .string(sdp)], field: "sessionOffer")
    }
    public func stopSession(_ id: String) async throws {
        _ = try await post(Documents.stopSession, ["id": .string(id)], field: "stopSession", as: Bool.self)
    }
    /// Changes a multi-disc game's disc (from 1).
    public func setDisc(sessionId: String, disc: Int) async throws {
        _ = try await post(Documents.setDisc, ["sessionId": .string(sessionId), "disc": .int(disc)], field: "setDisc", as: Bool.self)
    }

    public func saveState(sessionId: String, slot: Int) async throws {
        _ = try await post(Documents.saveState, ["sessionId": .string(sessionId), "slot": .int(slot)], field: "saveState", as: Bool.self)
    }
    public func loadState(sessionId: String, slot: Int) async throws {
        _ = try await post(Documents.loadState, ["sessionId": .string(sessionId), "slot": .int(slot)], field: "loadState", as: Bool.self)
    }

    /// The mappings in force for this user on a system (nil: on every system), one per model:
    /// their own for the system, their own for every system, the default for the system, the
    /// default for every system. A model missing from the list uses the built-in defaults.
    public func controllerMappings(system: String?) async throws -> [ControllerMapping] {
        try await post(Documents.controllerMappings, ["system": Self.system(system)], field: "controllerMappings")
    }
    /// Saves a controller model's mapping for a system (nil: every system).
    @discardableResult
    public func saveControllerMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding]) async throws
        -> ControllerMapping
    {
        try await post(
            Documents.saveControllerMapping,
            Self.mappingVariables(controller: controller, system: system, name: name, bindings: bindings),
            field: "saveControllerMapping")
    }
    /// Removes the user's own mapping for a model on a system (nil: every system); returns
    /// whether it had one. What then applies comes from `controllerMappings` again.
    @discardableResult
    public func resetControllerMapping(controller: String, system: String?) async throws -> Bool {
        try await post(Documents.resetControllerMapping, Self.resetVariables(controller: controller, system: system),
                       field: "resetControllerMapping")
    }
    /// A system's buttons and pad, and the controllers' diagrams.
    public func controls(system: String) async throws -> ControlsInfo {
        let request = try Self.request(baseURL: baseURL, query: Documents.controls, variables: ["system": .string(system)])
        let (data, response) = try await session.data(for: request)
        return try Self.decodeData(ControlsInfo.self, from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func system(_ system: String?) -> GraphQLValue { system.map(GraphQLValue.string) ?? .null }

    static func mappingVariables(controller: String, system: String?, name: String, bindings: [ControllerBinding])
        -> [String: GraphQLValue]
    {
        [
            "controller": .string(controller),
            "system": Self.system(system),
            "name": .string(name),
            "bindings": .list(bindings.map { .object(["input": .string($0.input), "button": .string($0.button)]) }),
        ]
    }

    static func resetVariables(controller: String, system: String?) -> [String: GraphQLValue] {
        ["controller": .string(controller), "system": Self.system(system)]
    }
}

/// Decodes anything, for reading `errors` when `data` has an unexpected shape.
struct JSONNull: Decodable {
    init(from decoder: Decoder) throws {}
}

/// The mapping calls `Mappings` needs (`SovEmuAPI`, or a stand-in in tests).
public protocol ControllerMappingService: Sendable {
    func controllerMappings(system: String?) async throws -> [ControllerMapping]
    func saveControllerMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding]) async throws
        -> ControllerMapping
    func resetControllerMapping(controller: String, system: String?) async throws -> Bool
}

extension SovEmuAPI: ControllerMappingService {}
