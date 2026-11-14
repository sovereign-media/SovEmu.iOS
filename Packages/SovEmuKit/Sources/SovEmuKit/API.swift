import Foundation

// MARK: - Models: the JSON shapes of the SovEmu API (`SovEmu.Server`).

public struct User: Codable, Sendable, Equatable {
    public let id: Int64
    public let username: String
    public let isAdmin: Bool
}

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
    public let tags: String
    public let size: Int64
    public let lastPlayedAt: String?
    public let playCount: Int?
}

public struct SessionInfo: Codable, Sendable {
    public let id: String
    public let gameId: Int64
    public let system: String
    public let title: String
    public let core: String
    public let width: Int
    public let height: Int
    public let fps: Double
}

public struct SessionDescription: Codable, Sendable {
    public let type: String
    public let sdp: String
    public init(type: String, sdp: String) {
        self.type = type
        self.sdp = sdp
    }
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
    public let iceServers: [IceServer]
}

public struct APIError: Error, LocalizedError, Sendable {
    public let status: Int
    public let message: String
    public var errorDescription: String? { message }

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }
}

// MARK: - Client

/// Calls to the SovEmu API. The session cookie lives in `HTTPCookieStorage.shared`, so sign-in
/// survives relaunches.
public final class SovEmuAPI: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "api" + path))
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(status: status, message: message ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return data
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try Self.decoder.decode(T.self, from: try await send("GET", path))
    }

    private func post<T: Decodable>(_ path: String, _ body: (any Encodable)? = nil) async throws -> T {
        try Self.decoder.decode(T.self, from: try await send("POST", path, body: body))
    }

    public func status() async throws -> AuthStatus { try await get("/auth/status") }
    public func login(username: String, password: String) async throws -> User {
        try await post("/auth/login", ["username": username, "password": password])
    }
    public func logout() async throws { _ = try await send("POST", "/auth/logout") }
    public func config() async throws -> ClientConfig { try await get("/config") }
    public func systems() async throws -> [SystemSummary] { try await get("/systems") }
    public func games(system: String) async throws -> [Game] { try await get("/systems/\(system)/games") }
    public func startSession(gameId: Int64) async throws -> SessionInfo {
        try await post("/sessions", ["game_id": gameId])
    }
    public func offer(sessionId: String, _ offer: SessionDescription) async throws -> SessionDescription {
        try await post("/sessions/\(sessionId)/offer", offer)
    }
    public func stopSession(_ id: String) async throws { _ = try await send("DELETE", "/sessions/\(id)") }
    public func saveState(sessionId: String, slot: Int) async throws {
        _ = try await send("POST", "/sessions/\(sessionId)/states/\(slot)")
    }
    public func loadState(sessionId: String, slot: Int) async throws {
        _ = try await send("POST", "/sessions/\(sessionId)/states/\(slot)/load")
    }
}
