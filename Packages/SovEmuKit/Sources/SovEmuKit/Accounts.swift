// Accounts: several signed in per server, several servers per device, as SovEmu.Android's
// `core/Accounts.kt` (after Sovereign.Android's). `StoredAccountCodec` keeps Android's v1 wire
// format exactly. Stored and read by `AccountStore.swift`.
import Foundation

// MARK: - StoredAccount

/// One account signed in on this device, as Sovereign.Android keeps them: several stay signed in
/// at once, each with its own refresh token in `AccountStore`, and one is active. Only the active
/// one is ever refreshed: nothing spends the server's token endpoint on an account nobody has
/// picked.
///
/// `id` is minted on the device (a UUID) when the account is first stored and never changes; it
/// is not the server's user id. `subject` is the ID token's `sub`, the server's user id: signing
/// in to an account already on the device (the same `sub` on the same server) replaces that
/// account's session rather than adding a second one. `clientId` is the OAuth client the refresh
/// token was issued to, which every refresh and the revocation must use (nil: the device client).
/// `userName` labels the account (the ID token's `preferred_username`). `lastUsedAt` is when it
/// was last made active (wall clock, ms), for the picker's initial focus.
public struct StoredAccount: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let subject: String
    public var server: String
    public var clientId: String?
    public var userName: String?
    public var lastUsedAt: Int64

    public init(id: String, subject: String, server: String, clientId: String?, userName: String?, lastUsedAt: Int64) {
        (self.id, self.subject, self.server) = (id, subject, server)
        (self.clientId, self.userName, self.lastUsedAt) = (clientId, userName, lastUsedAt)
    }

    /// At most five accounts per server: the picker's two rows of three, one `Add user`.
    public static let maxPerServer = 5

    /// At most three servers per device, so *Choose a server* fits on one screen.
    public static let maxServers = 3

    /// What the account is shown as: its username, or `?` before one is known.
    public var label: String {
        guard let userName, !userName.isBlank else { return "?" }
        return userName
    }

    /// The first two characters of `label`, uppercased, for the account's disc.
    public var initials: String { String(label.prefix(2)).uppercased() }

    /// Whether this account belongs to the server at `address` (`sameServer`).
    public func isOn(_ address: String?) -> Bool { Self.sameServer(server, address) }

    /// Why a **new** account on `server` would not fit beside `accounts` (every account on the
    /// device), or nil when it fits. A sign-in that replaces an account already stored always
    /// fits. Nobody is ever signed out to make room.
    public static func refusalFor(_ accounts: [StoredAccount], server: String) -> AccountRefusal? {
        let here = accounts.count { $0.isOn(server) }
        if here >= maxPerServer { return .serverFull }
        let servers = Set(accounts.map { serverKey($0.server) }).count
        if here == 0 && servers >= maxServers { return .deviceFull }
        return nil
    }

    /// Whether two server addresses are the same server: case-insensitive, without the scheme and
    /// without a trailing slash, so a server reached over `https` one day and `http` the next
    /// keeps its accounts.
    public static func sameServer(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isBlank, !b.isBlank else { return false }
        return serverKey(a) == serverKey(b)
    }

    /// The comparable form of a server address (`sameServer`).
    public static func serverKey(_ address: String) -> String {
        let trimmed = address.trimmed.droppingTrailingSlashes.lowercased()
        guard let scheme = trimmed.range(of: "://") else { return trimmed }
        return String(trimmed[scheme.upperBound...])
    }
}

/// Why a sign-in that would add an account was refused. Its new token is revoked, and whoever was
/// signed in stays signed in.
public enum AccountRefusal: Sendable, Equatable {
    /// Its server already has `StoredAccount.maxPerServer` accounts on this device.
    case serverFull
    /// It is a new server, and the device already holds `StoredAccount.maxServers`.
    case deviceFull
    /// The server's answer had no ID token with a `sub`: there is nothing to key it on.
    case noIdentity

    public var message: String {
        switch self {
        case .serverFull: "This device can't hold another user."
        case .deviceFull: KnownServers.capLine
        case .noIdentity: "The server didn't say who signed in. Try again."
        }
    }

    /// `AuthError.code` of a refused account.
    public static let accountRefused = "account_refused"

    /// As the sign-in screen shows it (Android's `exception()`).
    public var error: AuthError { AuthError(status: 0, code: Self.accountRefused, message: message) }
}

/// What a launch does with the accounts stored for the current server.
public enum LaunchAccounts: Sendable, Equatable {
    /// None: the sign-in screen.
    case login
    /// One: straight to Home as it, as a single-account install always did.
    case restore
    /// Two or more: *Who's watching?*, with no token request until someone is chosen.
    case picker

    public static func decide(_ accounts: Int) -> LaunchAccounts {
        if accounts <= 0 { return .login }
        return accounts == 1 ? .restore : .picker
    }
}

// MARK: - Choose a server

/// One server the device holds accounts for, as *Choose a server* lists it: `address` is the one
/// in use's own address, else its first account's; `inUse` marks the server the app talks to now.
public struct KnownServer: Sendable, Equatable, Hashable {
    public let address: String
    public let accounts: [StoredAccount]
    public let inUse: Bool

    public init(address: String, accounts: [StoredAccount], inUse: Bool) {
        (self.address, self.accounts, self.inUse) = (address, accounts, inUse)
    }

    public var key: String { StoredAccount.serverKey(address) }

    /// `1 user` or `N users`, then `  ·  in use` on the current one.
    public var countLine: String { KnownServers.countLabel(accounts.count) + (inUse ? KnownServers.inUse : "") }

    public var removeTitle: String { "Remove \(address)?" }

    /// Names everyone removing it signs out.
    public var removeMessage: String {
        KnownServers.removePrefix + accounts.map(\.label).joined(separator: ", ") + "."
    }
}

/// *Choose a server*'s list and the decisions around it, as Sovereign.Android's.
public enum KnownServers {
    public static let title = "Choose a server"
    public static let hint = "Each server keeps its own users on this device."
    public static let addAServer = "Add a server"
    public static let inUse = "  ·  in use"
    public static let removePrefix = "Everyone signed in to it on this device will be signed out: "
    public static let remove = "Remove"
    public static let cancel = "Cancel"

    /// In `Add a server`'s place when the device holds `StoredAccount.maxServers`.
    public static let capLine = "This device holds 3 servers. Remove one to add another."

    public static func countLabel(_ count: Int) -> String { count == 1 ? "1 user" : "\(count) users" }

    public static func canAddServer(_ servers: Int) -> Bool { servers < StoredAccount.maxServers }

    /// Every server `accounts` are on, in the order they were added, `current` marked in use. A
    /// current server with no account is not listed: the list is of servers with someone to pick.
    public static func list(_ accounts: [StoredAccount], current: String?) -> [KnownServer] {
        var order: [String] = []
        var groups: [String: [StoredAccount]] = [:]
        for account in accounts {
            let key = StoredAccount.serverKey(account.server)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(account)
        }
        let currentAddress = current.flatMap { $0.isBlank ? nil : $0 }
        let currentKey = currentAddress.map(StoredAccount.serverKey)
        return order.compactMap { key in
            guard let members = groups[key], let first = members.first else { return nil }
            let inUse = key == currentKey
            let address = inUse ? (currentAddress ?? first.server).trimmed.droppingTrailingSlashes : first.server
            return KnownServer(address: address, accounts: members, inUse: inUse)
        }
    }

    /// The server a removal of `removed` leaves the cursor on, and the one the app moves to when
    /// it was in use: the next in the list, else the one before, else none (server setup).
    public static func successor(_ servers: [KnownServer], removed: KnownServer) -> KnownServer? {
        guard let index = servers.firstIndex(where: { $0.key == removed.key }) else { return nil }
        if index + 1 < servers.count { return servers[index + 1] }
        return index > 0 ? servers[index - 1] : nil
    }
}

// MARK: - The stored form

/// The stored form of the account list: one string, one record per line and one field per tab
/// behind a version line, every field escaped and every optional one marked present (`+`) or
/// absent (`-`). The same bytes as SovEmu.Android's. A stored blob is not trusted: anything
/// malformed yields a shorter list, never an error, so a damaged record cannot keep the app from
/// the accounts that decode.
public enum StoredAccountCodec {
    private static let version = "v1"
    private static let fields = 6

    public static func encode(_ accounts: [StoredAccount]) -> String {
        var out = version
        for a in accounts {
            out += "\n"
            out += [
                present(a.id), present(a.subject), present(a.server), optional(a.clientId), optional(a.userName),
                present(String(a.lastUsedAt)),
            ].joined(separator: "\t")
        }
        return out
    }

    public static func decode(_ blob: String?) -> [StoredAccount] {
        guard let blob, !blob.isBlank else { return [] }
        // Foundation's split, by UTF-16 unit: Swift's `Character` would keep a "\r\n" whole.
        let lines = blob.components(separatedBy: "\n")
        guard lines.first == version else { return [] }
        var seen = Set<String>()
        // One record per id: two sharing one token key would sign each other out.
        return lines.dropFirst().compactMap(record).filter { seen.insert($0.id).inserted }
    }

    private static func record(_ line: String) -> StoredAccount? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count == fields else { return nil }
        var values: [String?] = []
        for part in parts {
            guard let field = field(part) else { return nil }
            values.append(field.value)
        }
        guard let id = values[0], !id.isBlank, let subject = values[1], let server = values[2], !server.isBlank,
              let lastUsed = values[5].flatMap({ Int64($0) }) else { return nil }
        return StoredAccount(
            id: id, subject: subject, server: server, clientId: values[3], userName: values[4], lastUsedAt: lastUsed)
    }

    private struct Field { let value: String? }

    private static func field(_ raw: String) -> Field? {
        if raw == "-" { return Field(value: nil) }
        guard raw.hasPrefix("+") else { return nil }
        return unescape(String(raw.dropFirst())).map { Field(value: $0) }
    }

    private static func present(_ value: String) -> String { "+" + escape(value) }

    private static func optional(_ value: String?) -> String { value.map(present) ?? "-" }

    private static func escape(_ value: String) -> String {
        var out = String.UnicodeScalarView()
        for c in value.unicodeScalars {
            switch c {
            case "%": out.append(contentsOf: "%25".unicodeScalars)
            case "\t": out.append(contentsOf: "%09".unicodeScalars)
            case "\n": out.append(contentsOf: "%0A".unicodeScalars)
            case "\r": out.append(contentsOf: "%0D".unicodeScalars)
            default: out.append(c)
            }
        }
        return String(out)
    }

    private static func unescape(_ value: String) -> String? {
        guard value.contains("%") else { return value }
        let scalars = Array(value.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            guard c == "%" else {
                out.append(c)
                i += 1
                continue
            }
            guard i + 3 <= scalars.count else { return nil }
            switch String(String.UnicodeScalarView(scalars[(i + 1)..<(i + 3)])) {
            case "25": out.append("%")
            case "09": out.append("\t")
            case "0A": out.append("\n")
            case "0D": out.append("\r")
            default: return nil
            }
            i += 3
        }
        return String(out)
    }
}

// MARK: - ID token

/// What the app reads off an ID token: who signed in (`subject`, `sub`) and their username
/// (`preferred_username`). Not verified: the server checks every request regardless, and this only
/// keys and labels an account on the device. The access token is never decoded.
public struct IdToken: Sendable, Equatable {
    public let subject: String?
    public let userName: String?

    public init(subject: String?, userName: String?) { (self.subject, self.userName) = (subject, userName) }

    public static let empty = IdToken(subject: nil, userName: nil)

    /// Reads `token`; a missing or malformed one is `empty`, never a throw.
    public static func read(_ token: String?) -> IdToken {
        guard let token, !token.isBlank else { return empty }
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2, let payload = base64URLDecode(parts[1]) else { return empty }
        var subject: String?
        if let match = payload.firstMatch(of: #/"sub"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|(\d+))/#) {
            subject = (match.output.1.map(String.init)).flatMap { $0.isEmpty ? nil : $0 } ?? match.output.2.map(String.init)
        }
        var userName: String?
        if let match = payload.firstMatch(of: #/"preferred_username"\s*:\s*"((?:[^"\\]|\\.)*)"/#) {
            userName = String(match.output.1)
        }
        return IdToken(
            subject: subject.flatMap { $0.isBlank ? nil : $0 }, userName: userName.flatMap { $0.isBlank ? nil : $0 })
    }

    /// Base64url, padded or not (JWTs are not), as UTF-8; nil when it is neither.
    private static func base64URLDecode(_ text: String) -> String? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 { base64 += String(repeating: "=", count: 4 - base64.count % 4) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Kotlin's trim, isBlank and trimEnd('/')

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
    var droppingTrailingSlashes: String {
        var s = Substring(self)
        while s.hasSuffix("/") { s = s.dropLast() }
        return String(s)
    }
}
