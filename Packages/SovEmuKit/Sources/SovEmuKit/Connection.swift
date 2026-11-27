// Reaching a server: the person's proxy headers and the address typed on the sign-in form, as
// SovEmu.Android's `core/Connection.kt` (after Sovereign.Android's). `ServerAddress.check` is
// the address half of Android's `SignInFlow.check`. The headers reach every request SovEmuKit
// makes to the server: Apollo's (`CustomHeaderInterceptor`, an `HTTPInterceptor`) and
// `TokenClient`'s.
import Apollo
import Foundation

// MARK: - Custom headers

/// One proxy header the person added (a Cloudflare Access service token, a forward-auth header, a
/// shared secret), sent on every request to the server so it can sit behind an authenticating
/// proxy. Neither its value nor a dump of it ever shows the value: a value is a credential.
public struct CustomHeader: Sendable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public let name: String
    public let value: String

    public init(_ name: String, _ value: String) { (self.name, self.value) = (name, value) }

    /// Never the value.
    public var description: String { "CustomHeader(name=\(name))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["name": name]) }
}

/// The rules for proxy headers, as Sovereign.Android's (after its Roku channel's): at most
/// `maxHeaders`, names of RFC 7230 token characters only (a space or colon makes a malformed
/// request, a CR or LF is header injection), never a header the app sets itself, and one per name
/// whatever its case (HTTP names are case-insensitive: two would leave the proxy to choose).
public enum CustomHeaderRules {
    public static let maxHeaders = 5

    private static let nameChars = Set("!#$%&'*+-.^_`|~".unicodeScalars)

    /// Headers the app sets: a person's `Authorization` would fight the bearer token, and break
    /// the one request that carries none (asking a server how to sign in, which is the request
    /// these headers exist to get through a proxy); the rest frame or route the request.
    public static let reservedNames: Set<String> = ["authorization", "content-type", "content-length", "host"]

    public static func cleanName(_ text: String) -> String { text.trimmed }

    /// Strips CR and LF (request smuggling) rather than refusing them, then trims.
    public static func cleanValue(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\r" && $0 != "\n" })).trimmed
    }

    /// Nil when `name` is usable, else a sentence for the screen saying which rule it broke.
    public static func nameError(_ name: String) -> String? {
        if name.isEmpty { return "Enter a header name." }
        if !name.unicodeScalars.allSatisfy(isNameChar) {
            return "A header name can only contain letters, digits and ! # $ % & ' * + - . ^ _ ` | ~ (no spaces or colons)."
        }
        if reservedNames.contains(name.lowercased()) { return "\"\(name)\" is set by the app and cannot be changed." }
        return nil
    }

    public static func valueError(_ value: String) -> String? { value.isEmpty ? "Enter a header value." : nil }

    /// Everything that must hold before `upsert`, in one answer: an edit (`replaceIndex` >= 0) or
    /// a name already there never counts against the cap.
    public static func validate(_ entries: [CustomHeader], name: String, value: String, replaceIndex: Int = -1) -> String? {
        if let error = nameError(name) ?? valueError(value) { return error }
        let new = replaceIndex < 0 && indexOfName(entries, name) == nil
        if new && entries.count >= maxHeaders { return "You can add up to \(maxHeaders) custom headers. Remove one first." }
        return nil
    }

    /// Adds a header, or replaces the one with that name (any case). An edit in place
    /// (`replaceIndex`) keeps its row, and its old name goes with it.
    public static func upsert(_ entries: [CustomHeader], name: String, value: String, replaceIndex: Int = -1) -> [CustomHeader] {
        let replacement = CustomHeader(name, value)
        var result: [CustomHeader] = []
        var placed = false
        for (i, current) in entries.enumerated() {
            if i == replaceIndex || current.name.caseInsensitiveCompare(name) == .orderedSame {
                if !placed {
                    result.append(replacement)
                    placed = true
                }
            } else {
                result.append(current)
            }
        }
        if !placed { result.append(replacement) }
        return result
    }

    public static func removeAt(_ entries: [CustomHeader], _ index: Int) -> [CustomHeader] {
        entries.enumerated().filter { $0.offset != index }.map(\.element)
    }

    public static func indexOfName(_ entries: [CustomHeader], _ name: String) -> Int? {
        entries.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Every rule again over a list that came from storage, which is not trusted: anything that
    /// would be refused at entry is dropped (first of a name wins), so a damaged store can never
    /// keep the app from a server it could otherwise reach.
    public static func sanitize(_ entries: [CustomHeader]) -> [CustomHeader] {
        var result: [CustomHeader] = []
        var seen = Set<String>()
        for entry in entries {
            if result.count >= maxHeaders { break }
            let name = cleanName(entry.name)
            let value = cleanValue(entry.value)
            if nameError(name) != nil || valueError(value) != nil { continue }
            if !seen.insert(name.lowercased()).inserted { continue }
            result.append(CustomHeader(name, value))
        }
        return result
    }

    /// The stored form: a line per header, a tab between name and value (neither can hold one).
    public static func encode(_ entries: [CustomHeader]) -> String {
        sanitize(entries).map { "\($0.name)\t\($0.value)" }.joined(separator: "\n")
    }

    public static func decode(_ blob: String?) -> [CustomHeader] {
        guard let blob, !blob.isBlank else { return [] }
        return sanitize(blob.components(separatedBy: "\n").compactMap { line in
            guard let tab = line.range(of: "\t"), tab.lowerBound > line.startIndex else { return nil }
            return CustomHeader(String(line[..<tab.lowerBound]), String(line[tab.upperBound...]))
        })
    }

    private static func isNameChar(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || nameChars.contains(c)
    }
}

/// Adds the person's proxy headers (`headers`) to every request to the `server` (its host and
/// port), and to nothing else: a value is usually a credential, for the server's proxy only. As
/// an Apollo `HTTPInterceptor` it covers GraphQL; `TokenClient` runs its requests through
/// `apply(to:)`. The headers are read on every request, so a change applies at once.
public struct CustomHeaderInterceptor: HTTPInterceptor {
    private let headers: @Sendable () -> [CustomHeader]
    private let server: @Sendable () -> String

    public init(headers: @escaping @Sendable () -> [CustomHeader], server: @escaping @Sendable () -> String) {
        (self.headers, self.server) = (headers, server)
    }

    /// `request` with the headers, when it goes to the server's host and port; else as it is.
    public func apply(to request: URLRequest) -> URLRequest {
        // Sanitized again: a header the app sets itself (`Authorization`) is never overridden.
        let all = CustomHeaderRules.sanitize(headers())
        guard !all.isEmpty, let target = URL(string: server()), let url = request.url, Self.sameOrigin(target, url) else {
            return request
        }
        var request = request
        for header in all { request.setValue(header.value, forHTTPHeaderField: header.name) }
        return request
    }

    public func intercept(request: URLRequest, next: NextHTTPInterceptorFunction) async throws -> HTTPResponse {
        try await next(apply(to: request))
    }

    /// The same host and port (a missing port is the scheme's), as OkHttp's `HttpUrl` compares.
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        guard let hostA = a.host()?.lowercased(), let hostB = b.host()?.lowercased(), hostA == hostB else { return false }
        return port(a) != nil && port(a) == port(b)
    }

    private static func port(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

// MARK: - The address typed

/// What to try, in order, for an address typed on the sign-in form, as Sovereign's: a bare host or
/// IP is asked over `https` first and `http` second, and *Secure connections only* (`secureOnly`)
/// drops the second. A server with TLS is then never talked to in the clear without anyone
/// knowing. An address typed with a scheme is used as typed, except `http://` under secure-only,
/// which is a contradiction: nothing to try, and the form says why.
public enum ServerAddress {
    private static let https = "https://"
    private static let http = "http://"

    /// What the form says for an `http://` address while secure-only is on.
    public static let insecure = "This address uses http. Turn off Secure connections only to connect to it."

    /// What the form says with no address typed.
    public static let empty = "Enter the server's address."

    public static func candidates(_ input: String, secureOnly: Bool) -> [String] {
        let trimmed = input.trimmed.droppingTrailingSlashes
        if trimmed.isEmpty { return [] }
        if hasPrefix(trimmed, https) { return [trimmed] }
        if hasPrefix(trimmed, http) { return secureOnly ? [] : [trimmed] }
        return secureOnly ? [https + trimmed] : [https + trimmed, http + trimmed]
    }

    /// Whether `input` names `http://`, which secure-only refuses.
    public static func isInsecure(_ input: String) -> Bool { hasPrefix(input.trimmed, http) }

    /// Whether `input` is (one way of writing) `server`, the address already in use.
    public static func names(_ input: String, server: String) -> Bool {
        !server.isEmpty && candidates(input, secureOnly: false).contains(server)
    }

    /// What `check` found.
    public enum Check: Sendable {
        /// The first candidate that answered, now the server, and its answer.
        case answered(address: String, config: BootstrapConfig)
        /// Nothing to try (`empty`, `insecure`) or nothing answered: why, for the form. The server
        /// is the one it was.
        case failed(String)
    }

    /// Asks the address typed, `input`, how to sign in: each of its `candidates` in turn (a bare
    /// host over https, then http unless `secureOnly`), the first that answers kept as the server,
    /// as Android's `SignInFlow.check`. One that never answers puts the last server back.
    public static func check(_ input: String, secureOnly: Bool, service: some ServerService) async throws -> Check {
        let candidates = candidates(input, secureOnly: secureOnly)
        if candidates.isEmpty { return .failed(isInsecure(input) ? insecure : empty) }
        let previous = await service.server()
        var last: (any Error)?
        for address in candidates {
            do {
                return .answered(address: address, config: try await service.bootstrap(at: address))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = error
            }
        }
        await service.setServer(previous)
        return .failed(reachFailure(last, address: nil))
    }

    private static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.lowercased().hasPrefix(prefix)
    }

    /// The server's own words (`APIError`, `AuthError`) as they are; else unreachable.
    static func reachFailure(_ error: (any Error)?, address: String?) -> String {
        if let error = error as? APIError { return error.message }
        if let error = error as? AuthError, let message = error.errorDescription { return message }
        let reason = error?.localizedDescription ?? "no answer"
        return address.map { "Cannot reach \($0): \(reason)" } ?? "Cannot reach the server: \(reason)"
    }
}
