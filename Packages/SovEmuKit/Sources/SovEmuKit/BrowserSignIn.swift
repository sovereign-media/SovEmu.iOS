import CryptoKit
import Foundation

// MARK: - Signing in through the system browser, as Sovereign's phones do
//
// The server's own sign-in page in `ASWebAuthenticationSession` (the app), the authorization code
// flow with PKCE as the mobile client, back to the app's scheme
// (`media.sovereign.sovemu:/oauth2redirect`). The app never sees the password. The pure half: the
// request and what came back; `TokenClient.finishBrowserSignIn` exchanges the code. Same as
// SovEmu.Android's `BrowserSignIn.kt`, with its cases.

/// A PKCE pair (RFC 7636): the verifier the app keeps, and the S256 challenge the browser carries.
/// 32 random bytes, base64url without padding: 43 characters.
public struct Pkce: Sendable, Equatable, CustomStringConvertible {
    let verifier: String
    public let challenge: String

    public static let method = "S256"

    init(verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(of: verifier)
    }

    static func generate() -> Pkce { Pkce(verifier: randomToken(bytes: 32)) }

    /// `BASE64URL(SHA256(ASCII(verifier)))`, RFC 7636 section 4.2.
    static func challenge(of verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    /// Never the verifier: it is what makes an intercepted code worthless.
    public var description: String { "Pkce(challenge: \(challenge))" }
}

/// One browser sign-in in flight: what the app holds between opening the browser and its
/// redirect. `state` binds the redirect to this request and `pkce` the code to this app; both are
/// made afresh for every attempt.
public struct BrowserSignInRequest: Sendable, Equatable, CustomStringConvertible {
    public let clientId: String
    public let redirectURI: String
    let authorization: URL
    public let state: String
    let pkce: Pkce

    init(clientId: String, redirectURI: String, authorization: URL, state: String = randomToken(bytes: 16), pkce: Pkce = .generate()) {
        (self.clientId, self.redirectURI, self.authorization, self.state, self.pkce) = (clientId, redirectURI, authorization, state, pkce)
    }

    /// The scheme the browser comes back on (`media.sovereign.sovemu`), for the session.
    public var callbackScheme: String { String(redirectURI.prefix { $0 != ":" }) }

    /// The URL for the system browser: the code flow with PKCE, and the scopes every sign-in asks for.
    public var authorizeURL: URL {
        var parts = URLComponents(url: authorization, resolvingAgainstBaseURL: true)!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: TokenClient.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: Pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        // `URLComponents` leaves `:` and `/` as they are in a query; the redirect URI is escaped
        // in full, as the server reads it.
        parts.percentEncodedQuery = parts.percentEncodedQuery?
            .replacingOccurrences(of: ":", with: "%3A").replacingOccurrences(of: "/", with: "%2F")
        return parts.url!
    }

    /// Never the verifier.
    public var description: String { "BrowserSignInRequest(clientId: \(clientId), state: \(state))" }
}

/// What came back on the redirect, judged against the request that was sent.
public enum BrowserRedirect: Sendable, Equatable {
    /// A code for this request: exchange it with the verifier.
    case code(String)
    /// The server answered this request with an OAuth error (`access_denied` …).
    case refused(error: String, description: String?)
    /// The `state` is missing or not this request's: never exchanged.
    case stateMismatch
    /// Not the app's redirect URI, or neither a code nor an error in it.
    case malformed

    /// Reads `url` for `request`. The state is checked first, before an error is believed:
    /// anything can open the scheme, and only the state proves the server sent it.
    public static func parse(_ url: URL, request: BrowserSignInRequest) -> BrowserRedirect {
        let text = url.absoluteString
        guard let at = text.firstIndex(of: "?"), String(text[..<at]) == request.redirectURI,
              let items = URLComponents(string: text)?.queryItems else { return .malformed }
        var params: [String: String] = [:]
        for item in items where params[item.name] == nil { params[item.name] = item.value ?? "" }
        guard params["state"] == request.state else { return .stateMismatch }
        if let error = params["error"], !error.isEmpty { return .refused(error: error, description: params["error_description"]) }
        guard let code = params["code"], !code.isEmpty else { return .malformed }
        return .code(code)
    }

    /// What a browser sign-in that did not sign in says, for people.
    public var message: String {
        switch self {
        case .code: ""
        case let .refused(_, description): description ?? "The sign-in was cancelled."
        case .stateMismatch: "That sign-in was not this one. Try again."
        case .malformed: "The browser came back without signing in. Try again."
        }
    }
}

func randomToken(bytes count: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return base64URL(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
