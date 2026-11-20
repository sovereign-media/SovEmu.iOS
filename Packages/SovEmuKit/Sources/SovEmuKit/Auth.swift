import Foundation
import Synchronization
#if canImport(Security)
import Security
#endif

// MARK: - Sign-in: the server's OAuth 2 endpoints, as its native (public) client
//
// Where to sign in comes from the server's `bootstrapConfig` (`SignInEndpoints`): the app
// hard-codes no path but `/graphql`. Sign in with a password (its `passwordEndpoint`), keep the access token in memory and the refresh token in a
// `RefreshTokenStore` (the Keychain in the app). Refresh tokens rotate: every refresh returns a
// new one, which replaces the old. "Signed in" means a refresh token is stored.

/// Where the refresh token lives between launches.
public protocol RefreshTokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

/// A refresh token kept only in memory (tests, previews).
public final class MemoryTokenStore: RefreshTokenStore {
    private let token: Mutex<String?>

    public init(_ token: String? = nil) { self.token = Mutex(token) }

    public func load() -> String? { token.withLock { $0 } }
    public func save(_ token: String) { self.token.withLock { $0 = token } }
    public func clear() { token.withLock { $0 = nil } }
}

#if canImport(Security)
/// The refresh token in the Keychain, one item per server address, readable after the first
/// unlock and never synced or restored to another device.
public struct KeychainTokenStore: RefreshTokenStore {
    public let service: String
    public let account: String

    public init(server: URL, service: String = "media.sovereign.sovemu.refresh-token") {
        self.service = service
        self.account = server.absoluteString
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}
#endif

/// A failed call to the token or password endpoint: the server's `error` code (`invalid_grant`,
/// `too_many_requests` …) and its `error_description`, which is meant for people.
public struct AuthError: Error, LocalizedError, Sendable, Equatable {
    public let status: Int
    public let code: String?
    public let message: String?

    public init(status: Int, code: String?, message: String?) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message ?? (status > 0 ? "Sign-in failed: \(HTTPURLResponse.localizedString(forStatusCode: status))." : "Sign-in failed.")
    }

    /// Wrong username or password (signing in), or a refresh token that is expired or revoked
    /// (refreshing: the app is signed out).
    public var isInvalidGrant: Bool { code == "invalid_grant" }

    /// No refresh token is stored, or the sign-in ended while a refresh was in flight.
    static let signedOut = AuthError(status: 0, code: "signed_out", message: "Sign in again.")

    /// The server's `bootstrapConfig` has not been read yet (an offline first start).
    static let notConfigured = AuthError(
        status: 0, code: "not_configured", message: "The server could not be reached to learn how to sign in.")

    /// The server has no password sign-in (`passwordEndpoint` is null).
    static let passwordUnavailable = AuthError(status: 0, code: "unsupported_grant_type", message: BootstrapConfig.codeOnlyMessage)
}

/// What the client needs from `bootstrapConfig` to sign in, refresh and sign out.
public struct SignInEndpoints: Codable, Sendable, Equatable {
    public let clientId: String
    public let token: URL
    public let revocation: URL?
    /// Nil when the server has turned password sign-in off.
    public let password: URL?

    public init(clientId: String, token: URL, revocation: URL?, password: URL?) {
        (self.clientId, self.token, self.revocation, self.password) = (clientId, token, revocation, password)
    }
}

/// The token endpoint's answer (also the password endpoint's).
struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Double?
    let refresh_token: String?
}

/// The token or password endpoint's answer when it refuses.
struct OAuthErrorBody: Decodable {
    let error: String
    let error_description: String?
}

/// Signs in, keeps the access token fresh and signs out. One refresh at a time: callers that
/// need a token while one is in flight wait for it (refresh tokens rotate, so two refreshes
/// with the same token would be one too many).
public actor TokenClient {
    public static let scope = "openid profile offline_access"
    /// Refresh when the access token has less than this left.
    static let margin: TimeInterval = 60

    public nonisolated let baseURL: URL
    /// From the server's `bootstrapConfig`; nil until it has been read.
    public private(set) var endpoints: SignInEndpoints?
    private nonisolated let store: any RefreshTokenStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let onSignedOut: (@Sendable () -> Void)?

    private var access: (token: String, expires: Date)?
    private var refreshing: Task<String, Error>?
    /// Bumped by every sign-in and sign-out, so a refresh that was in flight across one does
    /// not store its (now stale) answer.
    private var generation = 0

    /// - Parameter onSignedOut: called when the server refuses the refresh token
    ///   (`invalid_grant`): the tokens are gone and the app should show the sign-in screen.
    public init(
        baseURL: URL, endpoints: SignInEndpoints?, store: any RefreshTokenStore,
        session: URLSession = SovEmuAPI.makeSession(), now: @escaping @Sendable () -> Date = { Date() }, onSignedOut: (@Sendable () -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.endpoints = endpoints
        self.store = store
        self.session = session
        self.now = now
        self.onSignedOut = onSignedOut
    }

    /// A refresh token is stored.
    public nonisolated var isSignedIn: Bool { store.load() != nil }

    /// Takes the endpoints from a fresh `bootstrapConfig` (nil: the server offers no sign-in here).
    public func setEndpoints(_ endpoints: SignInEndpoints?) { self.endpoints = endpoints }

    /// Signs in with a password. Throws `AuthError` (with the server's description) when refused:
    /// `invalid_grant` (wrong password), `too_many_requests`, `unsupported_grant_type` (password
    /// sign-in turned off) …
    public func signIn(username: String, password: String) async throws {
        guard let endpoints else { throw AuthError.notConfigured }
        guard let passwordURL = endpoints.password else { throw AuthError.passwordUnavailable }
        // The server's own route for the apps' password sign-in (OAuth 2.1 has no password
        // grant): no `grant_type`, the same token answer and OAuth errors as the token endpoint.
        let tokens = try await requestToken(passwordURL, [
            ("client_id", endpoints.clientId), ("username", username), ("password", password), ("scope", Self.scope),
        ])
        guard tokens.refresh_token != nil else {
            throw AuthError(status: 200, code: "invalid_response", message: "The server did not return a refresh token.")
        }
        generation += 1
        refreshing = nil
        accept(tokens)
    }

    /// A current access token, refreshed first when it has under a minute left; nil when
    /// signed out.
    public func accessToken() async throws -> String? {
        if let access, access.expires.timeIntervalSince(now()) > Self.margin { return access.token }
        guard refreshing != nil || store.load() != nil else { return nil }
        return try await refresh(replacing: access?.token)
    }

    /// Refreshes the access token (after the server rejected `stale`). When another caller has
    /// already replaced `stale`, returns that token without refreshing again; when a refresh is
    /// in flight, waits for it.
    public func refresh(replacing stale: String?) async throws -> String {
        if let access, access.token != stale, access.expires.timeIntervalSince(now()) > Self.margin { return access.token }
        if let refreshing { return try await refreshing.value }
        guard let refreshToken = store.load() else { throw AuthError.signedOut }
        let task = Task { try await self.performRefresh(refreshToken) }
        refreshing = task
        defer { if refreshing == task { refreshing = nil } }
        return try await task.value
    }

    private func performRefresh(_ refreshToken: String) async throws -> String {
        let started = generation
        let tokens: TokenResponse
        do {
            // Not configured is not refused: the sign-in stays for when the server answers.
            guard let endpoints else { throw AuthError.notConfigured }
            tokens = try await requestToken(endpoints.token, [
                ("grant_type", "refresh_token"), ("client_id", endpoints.clientId), ("refresh_token", refreshToken),
            ])
        } catch let error as AuthError where error.isInvalidGrant {
            // Unless the user signed in (or out) meanwhile, this sign-in is over.
            if generation == started {
                forget()
                onSignedOut?()
            }
            throw error
        }
        guard generation == started else { throw AuthError.signedOut }
        accept(tokens)
        return tokens.access_token
    }

    /// Revokes the sign-in on the server (if it can be reached) and forgets the tokens
    /// whatever happens.
    public func signOut() async {
        let token = store.load()
        forget()
        guard let token, let endpoints, let revocation = endpoints.revocation else { return }
        var request = Self.formRequest(revocation, [("token", token), ("client_id", endpoints.clientId)])
        request.timeoutInterval = 10
        _ = try? await session.data(for: request)
    }

    private func forget() {
        generation += 1
        store.clear()
        access = nil
        refreshing = nil
    }

    private func accept(_ tokens: TokenResponse) {
        // Rotation: the new refresh token replaces the old one.
        if let refresh = tokens.refresh_token { store.save(refresh) }
        access = (tokens.access_token, now().addingTimeInterval(tokens.expires_in ?? 3600))
    }

    private func requestToken(_ url: URL, _ fields: [(String, String)]) async throws -> TokenResponse {
        let request = Self.formRequest(url, fields)
        let (data, response) = try await session.data(for: request)
        return try Self.readToken(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func readToken(_ data: Data, status: Int) throws -> TokenResponse {
        if status == 200, let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data) { return tokens }
        if let failure = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) {
            throw AuthError(status: status, code: failure.error, message: failure.error_description)
        }
        throw AuthError(status: status, code: nil, message: status == 200 ? "The server's answer could not be read." : nil)
    }

    /// A `POST` of `application/x-www-form-urlencoded` fields, without cookies.
    static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(fields.map { "\(formEncode($0))=\(formEncode($1))" }.joined(separator: "&").utf8)
        return request
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
