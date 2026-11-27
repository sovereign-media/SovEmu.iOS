// SovEmu.Android's `ConnectionTest.kt`, case for case: its interceptor case runs against the stub
// server through `SovEmuAPI` and `TokenClient`, its `SignInFlow` case through
// `ServerAddress.check`.
import Foundation
import Testing
@testable import SovEmuKit

/// The app's server, as the sign-in form and the account screens move it: answers how to sign in
/// only at `up` (and nowhere in `down`).
actor FakeServers: ServerService {
    private(set) var current: String
    private(set) var asked: [String] = []
    private let up: Set<String>?
    private let down: Set<String>

    init(_ current: String = "", up: Set<String>? = nil, down: Set<String> = []) {
        (self.current, self.up, self.down) = (current, up, down)
    }

    func server() -> String { current }
    func setServer(_ address: String) { current = address }

    func bootstrap(at address: String) throws -> BootstrapConfig {
        asked.append(address)
        current = address
        if down.contains(address) || (up.map { !$0.contains(address) } ?? false) { throw URLError(.cannotConnectToHost) }
        return BootstrapConfig(signInAvailable: true, address: address, deviceClientId: "c", tokenEndpoint: "/t")
    }
}

struct ConnectionTests {
    private func h(_ name: String, _ value: String = "v") -> CustomHeader { CustomHeader(name, value) }

    @Test func aHeaderNameMustBeATokenAndNotTheApps() {
        #expect(CustomHeaderRules.nameError("CF-Access-Client-Id") == nil)
        #expect(CustomHeaderRules.nameError("X Bad")?.contains("no spaces") == true)
        #expect(CustomHeaderRules.nameError("X:Bad")?.contains("no spaces") == true)
        #expect(CustomHeaderRules.nameError("Authorization")?.contains("set by the app") == true)
        #expect(CustomHeaderRules.nameError("") == "Enter a header name.")
        #expect(CustomHeaderRules.cleanValue(" a\r\nbc ") == "abc")
    }

    /// Two of one name would leave the proxy to choose.
    @Test func oneHeaderPerNameWhateverItsCaseAndFiveAtMost() {
        let one = CustomHeaderRules.upsert([], name: "X-Token", value: "a")
        let replaced = CustomHeaderRules.upsert(one + [h("Other")], name: "x-token", value: "b")
        #expect(replaced == [h("x-token", "b"), h("Other")])
        // An edit in place keeps its row, and its old name goes.
        #expect(CustomHeaderRules.upsert(replaced, name: "Renamed", value: "c", replaceIndex: 0) == [h("Renamed", "c"), h("Other")])
        let five = (1...5).map { h("H\($0)") }
        #expect(CustomHeaderRules.validate(five, name: "H6", value: "v")?.contains("up to 5") == true)
        #expect(CustomHeaderRules.validate(five, name: "h3", value: "new") == nil)
        #expect(CustomHeaderRules.validate(five, name: "Other", value: "v", replaceIndex: 2) == nil)
    }

    /// A damaged store must never keep the app from a server it could otherwise reach, and a
    /// header's value is never printed.
    @Test func aDamagedStoreKeepsWhatIsUsable() {
        let blob = "X-Token\ta\nbad line\nAuthorization\tsecret\nx-token\tdup\nY\tb\nZ\t"
        #expect(CustomHeaderRules.decode(blob) == [h("X-Token", "a"), h("Y", "b")])
        let headers = [h("A", "1"), h("B", "2")]
        #expect(CustomHeaderRules.decode(CustomHeaderRules.encode(headers)) == headers)
        #expect(CustomHeaderRules.decode(nil).isEmpty)
        #expect(h("A", "secret").description == "CustomHeader(name=A)")
        #expect(!String(reflecting: h("A", "secret")).contains("secret"))
        var dumped = ""
        dump(h("A", "secret"), to: &dumped)
        #expect(!dumped.contains("secret"))
    }

    /// A server with TLS is never talked to in the clear without anyone knowing.
    @Test func aBareAddressIsAskedOverHttpsFirst() {
        #expect(ServerAddress.candidates(" tv.local:8080/ ", secureOnly: false) == ["https://tv.local:8080", "http://tv.local:8080"])
        #expect(ServerAddress.candidates("tv.local", secureOnly: true) == ["https://tv.local"])
        #expect(ServerAddress.candidates("http://x", secureOnly: false) == ["http://x"])
        #expect(ServerAddress.candidates("http://x", secureOnly: true).isEmpty)
        #expect(ServerAddress.candidates("HTTPS://x", secureOnly: true) == ["HTTPS://x"])
        #expect(ServerAddress.candidates("  ", secureOnly: false).isEmpty)
        #expect(ServerAddress.names("tv.local:8080", server: "http://tv.local:8080"))
    }

    /// A header value is usually a credential for the server's proxy: it must reach every request
    /// SovEmuKit makes to the server (GraphQL, signed in or not, and the token endpoint) and none
    /// to anywhere else, nor replace the bearer token.
    @Test func headersGoToTheServerAndNowhereElse() async throws {
        let server = Stub { seen, _ in seen.path == "/graphql" ? Stub.systems : Stub.tokens("a1", "r1") }
        let other = Stub { _, _ in Stub.tokens("a2", "r2") }
        let headers: @Sendable () -> [CustomHeader] = { [CustomHeader("CF-Access-Client-Id", "id"), CustomHeader("X-Secret", "s")] }
        func header(_ seen: Seen, _ name: String) -> String? {
            seen.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        // Signed out (no bearer), then signed in at the server's own token endpoint.
        _ = try await SovEmuAPI(baseURL: server.base, session: server.session, customHeaders: headers).systems()
        let auth = TokenClient(
            baseURL: server.base, endpoints: server.endpoints, store: MemoryTokenStore(), session: server.session,
            customHeaders: headers)
        try await auth.signIn(username: "ada", password: "pw")
        _ = try await SovEmuAPI(baseURL: server.base, auth: auth, session: server.session, customHeaders: headers).systems()
        let sent = server.requests
        #expect(sent.map(\.path) == ["/graphql", "/oauth/password", "/graphql"])
        for request in sent {
            #expect(header(request, "CF-Access-Client-Id") == "id")
            #expect(header(request, "X-Secret") == "s")
        }
        #expect(sent[2].authorization == "Bearer a1")

        // A token endpoint on another host is not the server's proxy.
        let elsewhere = TokenClient(
            baseURL: server.base, endpoints: Stub.endpoints(other.base), store: MemoryTokenStore(), session: server.session,
            customHeaders: headers)
        try await elsewhere.signIn(username: "ada", password: "pw")
        #expect(other.requests.count == 1)
        #expect(other.requests.first.flatMap { header($0, "X-Secret") } == nil)

        // Nor is another port on the same host.
        let interceptor = CustomHeaderInterceptor(headers: headers, server: { "http://tv.local:8080" })
        #expect(interceptor.apply(to: URLRequest(url: URL(string: "http://tv.local:8081/graphql")!)).value(forHTTPHeaderField: "X-Secret") == nil)
        #expect(interceptor.apply(to: URLRequest(url: URL(string: "http://TV.local:8080/x")!)).value(forHTTPHeaderField: "X-Secret") == "s")
        let https = CustomHeaderInterceptor(headers: headers, server: { "https://tv.local" })
        #expect(https.apply(to: URLRequest(url: URL(string: "https://tv.local:443/graphql")!)).value(forHTTPHeaderField: "X-Secret") == "s")
    }

    @Test func aServerWithoutTlsIsReachedOverHttpUnlessSecureOnly() async throws {
        let service = FakeServers(up: ["http://tv.local:8080"])
        let check = try await ServerAddress.check("tv.local:8080", secureOnly: false, service: service)
        #expect(await service.asked == ["https://tv.local:8080", "http://tv.local:8080"])
        guard case .answered(let address, let config) = check else { Issue.record("no answer: \(check)"); return }
        #expect(address == "http://tv.local:8080")
        #expect(config.address == "http://tv.local:8080")

        let strict = FakeServers(up: ["http://tv.local:8080"])
        let refused = try await ServerAddress.check("tv.local:8080", secureOnly: true, service: strict)
        #expect(await strict.asked == ["https://tv.local:8080"])
        guard case .failed = refused else { Issue.record("answered under secure-only"); return }
        #expect(await strict.current == "", "the address it was on comes back")
        let insecure = try await ServerAddress.check("http://tv.local:8080", secureOnly: true, service: strict)
        guard case .failed(let message) = insecure else { Issue.record("answered an http address"); return }
        #expect(message == ServerAddress.insecure)
        #expect(await strict.asked.count == 1)
    }
}
