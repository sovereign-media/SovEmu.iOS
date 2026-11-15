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

    static let fields = "id gameId system title core width height fps connected"
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

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
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
    static let saveState = "mutation SaveState($sessionId: ID!, $slot: Int!) { saveState(sessionId: $sessionId, slot: $slot) }"
    static let loadState = "mutation LoadState($sessionId: ID!, $slot: Int!) { loadState(sessionId: $sessionId, slot: $slot) }"
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
    public func saveState(sessionId: String, slot: Int) async throws {
        _ = try await post(Documents.saveState, ["sessionId": .string(sessionId), "slot": .int(slot)], field: "saveState", as: Bool.self)
    }
    public func loadState(sessionId: String, slot: Int) async throws {
        _ = try await post(Documents.loadState, ["sessionId": .string(sessionId), "slot": .int(slot)], field: "loadState", as: Bool.self)
    }
}

/// Decodes anything, for reading `errors` when `data` has an unexpected shape.
struct JSONNull: Decodable {
    init(from decoder: Decoder) throws {}
}
