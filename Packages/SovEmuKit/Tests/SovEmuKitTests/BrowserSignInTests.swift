import Foundation
import Testing
@testable import SovEmuKit

/// Signing in through the browser, and *Sign in a TV*: SovEmu.Android's `BrowserSignInTest` and
/// `TvSignInTest` cases, and the exchange, refresh and sign-out as the mobile client.
struct BrowserSignInTests {
    private let redirect = "media.sovereign.sovemu:/oauth2redirect"
    private var request: BrowserSignInRequest {
        BrowserSignInRequest(clientId: "mobile-id", redirectURI: redirect, authorization: URL(string: "http://tv.local/oauth/authorize")!)
    }

    @Test func pkceIsRfc7636s() {
        // RFC 7636 appendix B's example.
        #expect(Pkce(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk").challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let pkce = Pkce.generate()
        #expect(pkce.verifier.count == 43)
        #expect(!pkce.description.contains(pkce.verifier), "the verifier never goes in a log line")
        #expect(!request.description.contains(request.pkce.verifier))
    }

    @Test func theRequestIsTheCodeFlowWithPkceAsTheMobileClient() {
        let request = self.request
        let url = request.authorizeURL.absoluteString
        #expect(url.hasPrefix("http://tv.local/oauth/authorize?"))
        for part in [
            "client_id=mobile-id", "response_type=code", "redirect_uri=media.sovereign.sovemu%3A%2Foauth2redirect",
            "scope=openid%20profile%20offline_access", "code_challenge=\(request.pkce.challenge)",
            "code_challenge_method=S256", "state=\(request.state)",
        ] {
            #expect(url.contains(part), "\(part)")
        }
        #expect(!url.contains(request.pkce.verifier))
        #expect(request.callbackScheme == "media.sovereign.sovemu")
    }

    @Test func theRedirectIsBelievedOnlyWithThisRequestsState() {
        let request = self.request
        func parse(_ s: String) -> BrowserRedirect { BrowserRedirect.parse(URL(string: s)!, request: request) }
        #expect(parse("\(redirect)?code=abc&state=\(request.state)&iss=x") == .code("abc"))
        // The state first: an error is believed only when the server sent it.
        #expect(parse("\(redirect)?error=access_denied&state=other") == .stateMismatch)
        #expect(parse("\(redirect)?code=abc") == .stateMismatch)
        #expect(parse("\(redirect)?error=access_denied&error_description=no%20thanks&state=\(request.state)")
            == .refused(error: "access_denied", description: "no thanks"))
        #expect(parse("media.sovereign.sovemu:/elsewhere?code=a&state=\(request.state)") == .malformed)
        #expect(parse("\(redirect)?state=\(request.state)") == .malformed)
    }

    @Test func aBrowserSignInRefreshesAndSignsOutAsTheMobileClient() async throws {
        let answers: [(Int, String)] = [Stub.tokens("a1", "r1", expiresIn: 30), Stub.tokens("a2", "r2"), (200, "")]
        let count = Counter()
        let stub = Stub { _, _ in answers[count.next() - 1] }
        let store = MemoryTokenStore()
        let endpoints = SignInEndpoints(
            clientId: "device-id", token: stub.base.appending(path: "oauth/token"), revocation: stub.base.appending(path: "oauth/revoke"),
            password: nil, authorization: stub.base.appending(path: "oauth/authorize"), mobileClientId: "mobile-id", mobileRedirectURI: redirect)
        let client = TokenClient(baseURL: stub.base, endpoints: endpoints, store: store, session: stub.session)
        let request = try #require(await client.browserSignInRequest())
        try await client.finishBrowserSignIn(URL(string: "\(redirect)?code=the-code&state=\(request.state)")!, request: request)
        #expect(stub.requests[0].form == [
            "grant_type": "authorization_code", "client_id": "mobile-id", "code": "the-code", "redirect_uri": redirect,
            "code_verifier": request.pkce.verifier,
        ])
        #expect(store.load() == "r1" && store.loadClientId() == "mobile-id")
        // A refresh token is good only with its own client: the browser's is the mobile client's.
        #expect(try await client.accessToken() == "a2")
        #expect(stub.requests[1].form["client_id"] == "mobile-id")
        await client.signOut()
        #expect(stub.requests[2].form["client_id"] == "mobile-id")
        #expect(store.load() == nil && store.loadClientId() == nil)
    }

    @Test func aRedirectThatIsNotThisSignInsIsNeverExchanged() async throws {
        let stub = Stub { _, _ in Stub.tokens("a", "r") }
        let endpoints = SignInEndpoints(
            clientId: "device-id", token: stub.base.appending(path: "oauth/token"), revocation: nil, password: nil,
            authorization: stub.base.appending(path: "oauth/authorize"), mobileClientId: "mobile-id", mobileRedirectURI: redirect)
        let client = TokenClient(baseURL: stub.base, endpoints: endpoints, store: MemoryTokenStore(), session: stub.session)
        let request = try #require(await client.browserSignInRequest())
        await #expect(throws: AuthError.self) {
            try await client.finishBrowserSignIn(URL(string: "\(redirect)?code=stolen&state=other")!, request: request)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func aTvsCodeIsTakenAsTypedOrPasted() {
        for typed in ["qg3w ry4w", "QG3W-RY4W", " QG3WRY4W ", "qg3w-ry4w-extra"] {
            #expect(TvSignIn.format(typed) == "QG3W-RY4W", "\(typed)")
        }
        #expect(TvSignIn.isComplete("QG3WRY4W") && !TvSignIn.isComplete("QG3W-RY4"))
        #expect(TvSignIn.confirmation(server: "http://192.168.1.10:8080", name: "ada") == "Sign in a TV to http://192.168.1.10:8080 as ada?")
        #expect(TvSignIn.failure(APIError(status: 200, code: "NOT_FOUND", message: "x")).hasPrefix("No TV is waiting with that code"))
        #expect(TvSignIn.failure(APIError(status: 200, code: "TOO_MANY_REQUESTS", message: "x")).hasPrefix("Too many codes"))
    }
}
