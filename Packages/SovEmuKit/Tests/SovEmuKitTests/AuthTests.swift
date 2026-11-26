import Foundation
import Synchronization
import Testing
@testable import SovEmuKit

/// A request a stub server saw: its path, headers and form fields (or GraphQL body).
struct Seen: Sendable {
    let path: String
    let authorization: String?
    let cookie: String?
    let form: [String: String]
}

/// A stand-in server for one test, reached through `URLProtocol`: each stub gets its own host,
/// so tests running in parallel do not see each other's requests.
final class Stub: Sendable {
    typealias Handler = @Sendable (Seen, Data) async -> (status: Int, body: String)

    let base: URL
    let session: URLSession
    private let seen = Log()

    final class Log: Sendable {
        let items = Mutex<[Seen]>([])
    }

    init(_ handler: @escaping Handler) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        base = URL(string: "http://\(host):8080")!
        let configuration = SovEmuAPI.sessionConfiguration()
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
        let seen = self.seen
        StubProtocol.handlers.withLock {
            $0[host] = { request, body in
                seen.items.withLock { $0.append(request) }
                return await handler(request, body)
            }
        }
    }

    /// The endpoints the server's `bootstrapConfig` names by default.
    var endpoints: SignInEndpoints { Self.endpoints(base) }

    static func endpoints(_ base: URL) -> SignInEndpoints {
        SignInEndpoints(
            clientId: "sovemu-native", token: base.appending(path: "oauth/token"),
            revocation: base.appending(path: "oauth/revoke"), password: base.appending(path: "oauth/password"))
    }

    var requests: [Seen] { seen.items.withLock { $0 } }
    func requests(to path: String) -> [Seen] { requests.filter { $0.path == path } }

    static func json(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    static func tokens(_ access: String, _ refresh: String, expiresIn: Int = 3600) -> (Int, String) {
        (200, json(["access_token": access, "token_type": "Bearer", "expires_in": expiresIn, "refresh_token": refresh,
                    "id_token": "x.y.z", "scope": TokenClient.scope]))
    }

    static func oauthError(_ status: Int, _ code: String, _ description: String) -> (Int, String) {
        (status, json(["error": code, "error_description": description]))
    }

    static let unauthenticated = (200, #"{"data":null,"errors":[{"message":"sign in first","extensions":{"code":"UNAUTHENTICATED"}}]}"#)
    static let systems = (200, #"{"data":{"systems":[]}}"#)
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let handlers = Mutex<[String: Stub.Handler]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let request = self.request
        guard let url = request.url, let host = url.host(), let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let body = Self.body(of: request)
        var form: [String: String] = [:]
        if request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded" {
            for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                form[parts[0]] = parts.count > 1 ? parts[1] : ""
            }
        }
        let seen = Seen(
            path: url.path(), authorization: request.value(forHTTPHeaderField: "Authorization"),
            cookie: request.value(forHTTPHeaderField: "Cookie"), form: form)
        // URLProtocol and its client predate Sendable; the client is safe to call from any thread.
        struct Loading: @unchecked Sendable { let request: URLProtocol, client: (any URLProtocolClient)? }
        let loading = Loading(request: self, client: client)
        Task {
            let (status, answer) = await handler(seen, body)
            let text = url.path() == "/graphql" ? Typenames.add(answer) : answer
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            loading.client?.urlProtocol(loading.request, didReceive: response, cacheStoragePolicy: .notAllowed)
            loading.client?.urlProtocol(loading.request, didLoad: Data(text.utf8))
            loading.client?.urlProtocolDidFinishLoading(loading.request)
        }
    }

    /// URLSession hands a protocol the body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Counts calls from `@Sendable` closures.
final class Counter: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { $0 += 1; return $0 } }
    var count: Int { value.withLock { $0 } }
}

/// Sign-in with the password grant, refresh (rotation, single flight, `invalid_grant`), sign-out,
/// and the API's bearer header and retry, against the spec of `/oauth/token` and `/oauth/revoke`.
struct AuthTests {
    @Test func signsInWithAPasswordAtItsOwnRoute() async throws {
        let stub = Stub { _, _ in Stub.tokens("a1", "r1") }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        #expect(!auth.isSignedIn)

        try await auth.signIn(username: "ada lovelace", password: "p&ss=w0rd")
        #expect(stub.requests.map(\.path) == ["/oauth/password"])
        let request = try #require(stub.requests.first)
        #expect(request.form == [
            "client_id": "sovemu-native", "username": "ada lovelace", "password": "p&ss=w0rd",
            "scope": "openid profile offline_access",
        ], "no grant_type")
        #expect(store.load() == "r1" && auth.isSignedIn)
        // The access token is kept in memory and used until it nears its expiry.
        #expect(try await auth.accessToken() == "a1")
        #expect(stub.requests.count == 1)
        // Spaces and reserved characters are percent-encoded on the wire.
        #expect(TokenClient.formEncode("openid profile") == "openid%20profile")
        #expect(TokenClient.formEncode("a&b=c+d") == "a%26b%3Dc%2Bd")
    }

    @Test func wrongPasswordShowsTheServersDescription() async throws {
        let stub = Stub { _, _ in Stub.oauthError(400, "invalid_grant", "Wrong username or password.") }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        let error = try await #require(throws: AuthError.self) { try await auth.signIn(username: "ada", password: "nope") }
        #expect(error.isInvalidGrant && error.status == 400)
        #expect(error.localizedDescription == "Wrong username or password.")
        #expect(store.load() == nil && !auth.isSignedIn)
        #expect(try await auth.accessToken() == nil)

        let throttled = Stub { _, _ in Stub.oauthError(429, "too_many_requests", "Too many attempts: try again in 5 minutes.") }
        let limited = TokenClient(baseURL: throttled.base, endpoints: throttled.endpoints, store: MemoryTokenStore(), session: throttled.session)
        let wait = try await #require(throws: AuthError.self) { try await limited.signIn(username: "ada", password: "x") }
        #expect(wait.code == "too_many_requests" && wait.localizedDescription == "Too many attempts: try again in 5 minutes.")

        // An answer that is not the OAuth error shape still says something.
        let broken = Stub { _, _ in (502, "<html>") }
        let gateway = TokenClient(baseURL: broken.base, endpoints: broken.endpoints, store: MemoryTokenStore(), session: broken.session)
        let bad = try await #require(throws: AuthError.self) { try await gateway.signIn(username: "ada", password: "x") }
        #expect(bad.status == 502 && bad.code == nil && !(bad.errorDescription ?? "").isEmpty)

        // A server with password sign-in turned off says so, and that is shown like the rest.
        let off = Stub { _, _ in Stub.oauthError(400, "unsupported_grant_type", "Password sign-in is turned off on this server.") }
        let disabled = TokenClient(baseURL: off.base, endpoints: off.endpoints, store: MemoryTokenStore(), session: off.session)
        let refused = try await #require(throws: AuthError.self) { try await disabled.signIn(username: "ada", password: "x") }
        #expect(refused.code == "unsupported_grant_type" && refused.localizedDescription == "Password sign-in is turned off on this server.")
    }

    @Test func refreshRotatesTheStoredRefreshToken() async throws {
        let stub = Stub { request, _ in
            request.form["refresh_token"] == "r1" ? Stub.tokens("a2", "r2") : Stub.oauthError(400, "invalid_grant", "reused")
        }
        // A relaunch: the refresh token is stored, no access token yet.
        let store = MemoryTokenStore("r1")
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        #expect(auth.isSignedIn)
        #expect(try await auth.accessToken() == "a2")
        let request = try #require(stub.requests(to: "/oauth/token").first)
        #expect(request.form == ["grant_type": "refresh_token", "client_id": "sovemu-native", "refresh_token": "r1"])
        #expect(store.load() == "r2", "the new refresh token replaces the old")
    }

    @Test func refreshesWhenUnderAMinuteIsLeft() async throws {
        let refreshes = Counter()
        let stub = Stub { request, _ in
            request.path == "/oauth/password" ? Stub.tokens("a1", "r1", expiresIn: 3600)
                : Stub.tokens("a\(refreshes.next() + 1)", "r\(refreshes.count + 1)")
        }
        let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session, now: { clock.withLock { $0 } })
        try await auth.signIn(username: "ada", password: "pw")
        clock.withLock { $0 += 3600 - 61 }
        #expect(try await auth.accessToken() == "a1")
        clock.withLock { $0 += 2 }
        #expect(try await auth.accessToken() == "a2")
        #expect(refreshes.count == 1 && store.load() == "r2")
    }

    @Test func invalidGrantOnRefreshSignsOut() async throws {
        let stub = Stub { request, _ in
            switch request.path {
            case "/oauth/token": Stub.oauthError(400, "invalid_grant", "This sign-in has ended.")
            default: Stub.unauthenticated
            }
        }
        let signedOut = Counter()
        let store = MemoryTokenStore("revoked")
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session, onSignedOut: { _ = signedOut.next() })
        let api = SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session)

        // The API reports it as UNAUTHENTICATED, so the app has one thing to check.
        let error = try await #require(throws: APIError.self) { try await api.systems() }
        #expect(error.isUnauthenticated && error.message == "This sign-in has ended.")
        #expect(store.load() == nil && !api.isSignedIn)
        #expect(signedOut.count == 1)
        #expect(stub.requests(to: "/graphql").isEmpty, "nothing is sent with a token that could not be refreshed")
        // Signed out, the next call goes without a token and without refreshing again.
        _ = try? await api.systems()
        #expect(stub.requests(to: "/oauth/token").count == 1)
        #expect(stub.requests(to: "/graphql").first?.authorization == nil)
    }

    @Test func aNetworkFailureOnRefreshKeepsTheSignIn() async throws {
        let stub = Stub { _, _ in (503, "") }
        let store = MemoryTokenStore("r1")
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        let api = SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session)
        await #expect(throws: AuthError.self) { try await api.systems() }
        #expect(store.load() == "r1")
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let refreshes = Counter()
        let stub = Stub { _, _ in
            _ = refreshes.next()
            try? await Task.sleep(for: .milliseconds(100))
            return Stub.tokens("a2", "r2")
        }
        let store = MemoryTokenStore("r1")
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        let tokens = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<8 { group.addTask { try await auth.accessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(tokens == Array(repeating: "a2", count: 8))
        #expect(refreshes.count == 1)
        #expect(store.load() == "r2")
    }

    @Test func apiSendsTheBearerTokenAndRetriesOnceAfterUnauthenticated() async throws {
        let stub = Stub { request, _ in
            switch request.path {
            case "/oauth/password": return Stub.tokens("a1", "r1")
            case "/oauth/token":
                try? await Task.sleep(for: .milliseconds(50))
                return Stub.tokens("a2", "r2")
            default:
                // The server has revoked a1 (say it restarted with a new key).
                return request.authorization == "Bearer a2" ? Stub.systems : Stub.unauthenticated
            }
        }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        let api = SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session)
        try await api.signIn(username: "ada", password: "pw")

        // Several requests fail with a1 at once: one refresh, then each retries with a2.
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 { group.addTask { try await api.systems().count } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results == [0, 0, 0, 0])
        #expect(stub.requests(to: "/oauth/token").count == 1)
        #expect(stub.requests(to: "/oauth/token").allSatisfy { $0.form["grant_type"] == "refresh_token" })
        #expect(store.load() == "r2")
        let graphql = stub.requests(to: "/graphql")
        #expect(graphql.count == 8 && graphql.allSatisfy { $0.authorization?.hasPrefix("Bearer a") == true })
        #expect(graphql.allSatisfy { $0.cookie == nil }, "no cookies")

        // Only once: a token the server keeps refusing ends in the error, not a loop.
        let refusing = Stub { request, _ in request.path == "/graphql" ? Stub.unauthenticated : Stub.tokens("b", "r") }
        let stubborn = SovEmuAPI(
            baseURL: refusing.base, auth: TokenClient(baseURL: refusing.base, endpoints: refusing.endpoints, store: MemoryTokenStore("r0"), session: refusing.session),
            session: refusing.session)
        let error = try await #require(throws: APIError.self) { try await stubborn.systems() }
        #expect(error.isUnauthenticated)
        #expect(refusing.requests(to: "/graphql").count == 2)
    }

    @Test func viewerGoesWithoutATokenWhenSignedOut() async throws {
        let stub = Stub { _, _ in (200, #"{"data":{"viewer":{"setupRequired":true,"user":null}}}"#) }
        let api = SovEmuAPI(
            baseURL: stub.base, auth: TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: MemoryTokenStore(), session: stub.session), session: stub.session)
        #expect(try await api.status().setupRequired)
        #expect(stub.requests.map(\.path) == ["/graphql"])
        #expect(stub.requests.first?.authorization == nil)
    }

    @Test func signOutRevokesAndForgetsWhateverHappens() async throws {
        let stub = Stub { request, _ in request.path == "/oauth/revoke" ? (500, "") : Stub.tokens("a1", "r1") }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: store, session: stub.session)
        try await auth.signIn(username: "ada", password: "pw")
        await auth.signOut()
        let revoke = try #require(stub.requests(to: "/oauth/revoke").first)
        #expect(revoke.form == ["token": "r1", "client_id": "sovemu-native"])
        #expect(store.load() == nil && !auth.isSignedIn)
        #expect(try await auth.accessToken() == nil)

        // Offline: still signed out.
        let nowhere = URL(string: "http://unreachable.test:8080")!
        let offline = TokenClient(
            baseURL: nowhere, endpoints: Stub.endpoints(nowhere), store: MemoryTokenStore("r9"), session: stub.session)
        await offline.signOut()
        #expect(!offline.isSignedIn)
    }
}

/// `bootstrapConfig`: the anonymous query the app asks first, whose answer names the client id
/// and every sign-in URL (the app hard-codes no path but `/graphql`).
struct BootstrapTests {
    /// The server's answer: every field the query selects, null where `config` names none.
    static func reply(_ config: [String: Any?]) -> (Int, String) {
        let selected = [
            "signInAvailable", "address", "issuer", "webClientId", "deviceClientId", "authorizationEndpoint", "tokenEndpoint",
            "revocationEndpoint", "deviceAuthorizationEndpoint", "verificationUri", "passwordEndpoint",
            "mobileClientId", "mobileRedirectUri",
        ]
        let fields = Dictionary(uniqueKeysWithValues: selected.map { ($0, (config[$0] ?? nil) ?? NSNull()) })
        return (200, Stub.json(["data": ["bootstrapConfig": fields]]))
    }

    @Test func theAnswerDrivesTheUrlsAndClientId() async throws {
        let stub = Stub { request, _ in
            switch request.path {
            case "/graphql":
                // Paths the app could not guess, to show it takes them from the answer.
                Self.reply([
                    "signInAvailable": true, "address": "stub", "issuer": "http://stub", "webClientId": "web",
                    "deviceClientId": "phone-app", "authorizationEndpoint": "/sso/authorize", "tokenEndpoint": "/sso/token",
                    "revocationEndpoint": "/sso/revoke", "deviceAuthorizationEndpoint": "/sso/device", "verificationUri": "/link",
                    "passwordEndpoint": "/sso/native/password",
                ])
            case "/sso/native/password": Stub.tokens("a1", "r1")
            case "/sso/token": Stub.tokens("a2", "r2")
            default: (404, "")
            }
        }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: nil, store: store, session: stub.session)
        let api = SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session)

        let config = try await api.bootstrap()
        #expect(config.signInProblem == nil)
        #expect(stub.requests.first?.authorization == nil, "asked without a token")
        // Relative endpoints are resolved against the server address.
        #expect(await auth.endpoints == SignInEndpoints(
            clientId: "phone-app", token: stub.base.appending(path: "sso/token"),
            revocation: stub.base.appending(path: "sso/revoke"), password: stub.base.appending(path: "sso/native/password"),
            deviceAuthorization: stub.base.appending(path: "sso/device"), authorization: stub.base.appending(path: "sso/authorize")))

        try await api.signIn(username: "ada", password: "pw")
        #expect(try await auth.refresh(replacing: "a1") == "a2")
        await api.signOut()
        #expect(stub.requests.map(\.path) == ["/graphql", "/sso/native/password", "/sso/token", "/sso/revoke"])
        #expect(stub.requests.dropFirst().allSatisfy { $0.form["client_id"] == "phone-app" })
        #expect(store.load() == nil)
    }

    @Test func anAddressOutsidePublicUrlCannotSignIn() async throws {
        let stub = Stub { _, _ in Self.reply(["signInAvailable": false, "address": "192.168.1.20:8080"]) }
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: MemoryTokenStore(), session: stub.session)
        let config = try await SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session).bootstrap()
        #expect(config.signInProblem == "Signing in isn't available at 192.168.1.20:8080. Add it to SOVEMU_PUBLIC_URL on the server.")
        #expect(config.endpoints(relativeTo: stub.base) == nil)
        #expect(await auth.endpoints == nil, "a fresh answer replaces the stored endpoints")
        await #expect(throws: AuthError.notConfigured) { try await auth.signIn(username: "ada", password: "pw") }
        #expect(stub.requests.count == 1)
    }

    @Test func aServerWithoutPasswordSignInSaysSo() async throws {
        let stub = Stub { _, _ in
            Self.reply([
                "signInAvailable": true, "address": "tv.local", "deviceClientId": "sovemu-native",
                "tokenEndpoint": "http://tv.local/oauth/token", "revocationEndpoint": "http://tv.local/oauth/revoke",
                "deviceAuthorizationEndpoint": "http://tv.local/oauth/device_authorization", "passwordEndpoint": nil,
            ])
        }
        let store = MemoryTokenStore()
        let auth = TokenClient(baseURL: stub.base, endpoints: nil, store: store, session: stub.session)
        let config = try await SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session).bootstrap()
        // A code still signs in: no problem, only no password.
        #expect(config.signInProblem == nil)
        #expect(config.canPair && !config.canUsePassword)
        let message = "This server signs in only with a code shown on the screen."
        // Refresh and sign-out still have their endpoints; only the password is missing.
        let endpoints = await auth.endpoints
        #expect(endpoints?.password == nil && endpoints?.token.absoluteString == "http://tv.local/oauth/token")
        let error = try await #require(throws: AuthError.self) { try await auth.signIn(username: "ada", password: "pw") }
        #expect(error.localizedDescription == message)
        #expect(stub.requests.count == 1, "nothing sent")
    }

    @Test func refreshWaitsForTheBootstrapAnswerWithoutSigningOut() async throws {
        let stub = Stub { _, _ in (500, "") }
        let store = MemoryTokenStore("r1")
        let auth = TokenClient(baseURL: stub.base, endpoints: nil, store: store, session: stub.session)
        await #expect(throws: AuthError.notConfigured) { try await auth.accessToken() }
        #expect(store.load() == "r1" && stub.requests.isEmpty)
    }

    @Test func asksForEveryEndpointItSignsInWith() throws {
        let document = SovEmuGraphQL.BootstrapQuery.operationDocument.definition?.queryDocument ?? ""
        for field in ["signInAvailable", "address", "deviceClientId", "tokenEndpoint", "revocationEndpoint", "passwordEndpoint"] {
            #expect(document.contains(field), "\(field)")
        }
        // A persisted answer reads back the same.
        let config = BootstrapConfig(signInAvailable: true, address: "a", deviceClientId: "n", tokenEndpoint: "http://a/t", passwordEndpoint: "http://a/p")
        #expect(try JSONDecoder().decode(BootstrapConfig.self, from: JSONEncoder().encode(config)) == config)
    }
}
