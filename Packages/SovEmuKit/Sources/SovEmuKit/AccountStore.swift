// Every account signed in on this device, as SovEmu.Android's `core/AccountStore.kt` (and its
// `Storage.kt`'s `KeyValue`). Android seals each refresh token with a Keystore key into its
// preferences; here the tokens go to the Keychain (`AccountTokenStore`), this device only, and
// the rest (the list, the active id, device names) to a `KeyValue` (UserDefaults in the app).
// The account halves of Android's `Session.launch`, `signedInWith` and `removeServer` are here
// too, so the app's session only adds its tokens and requests.
import Foundation
import Synchronization

// MARK: - Storage

/// A device's small key-value storage (UserDefaults in the app, `MemoryKeyValue` in tests).
public protocol KeyValue: Sendable {
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String)
    func remove(_ key: String)
}

/// `KeyValue` over UserDefaults, every key behind `prefix`.
public struct UserDefaultsKeyValue: KeyValue, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; it predates Sendable in some SDKs.
    private let defaults: UserDefaults
    private let prefix: String

    public init(_ defaults: UserDefaults = .standard, prefix: String = "") {
        (self.defaults, self.prefix) = (defaults, prefix)
    }

    public func get(_ key: String) -> String? { defaults.string(forKey: prefix + key) }
    public func put(_ key: String, _ value: String) { defaults.set(value, forKey: prefix + key) }
    public func remove(_ key: String) { defaults.removeObject(forKey: prefix + key) }
}

/// `KeyValue` in memory (tests, previews).
public final class MemoryKeyValue: KeyValue {
    private let map = Mutex<[String: String]>([:])

    public init(_ values: [String: String] = [:]) { map.withLock { $0 = values } }

    public var values: [String: String] { map.withLock { $0 } }
    public func get(_ key: String) -> String? { map.withLock { $0[key] } }
    public func put(_ key: String, _ value: String) { map.withLock { $0[key] = value } }
    public func remove(_ key: String) { _ = map.withLock { $0.removeValue(forKey: key) } }
}

/// Where each account's refresh token lives, by `StoredAccount.id`: the Keychain in the app
/// (`KeychainAccountTokenStore`), never the defaults. Android's `Sealer` plays this part there.
public protocol AccountTokenStore: Sendable {
    func load(_ id: String) -> String?
    func save(_ token: String, for id: String)
    func remove(_ id: String)
}

/// Account tokens in memory (tests, previews).
public final class MemoryAccountTokenStore: AccountTokenStore {
    private let tokens = Mutex<[String: String]>([:])

    public init(_ tokens: [String: String] = [:]) { self.tokens.withLock { $0 = tokens } }

    public var all: [String: String] { tokens.withLock { $0 } }
    public func load(_ id: String) -> String? { tokens.withLock { $0[id] } }
    public func save(_ token: String, for id: String) { tokens.withLock { $0[id] = token } }
    public func remove(_ id: String) { _ = tokens.withLock { $0.removeValue(forKey: id) } }
}

#if canImport(Security)
/// Each account's refresh token in the Keychain, one item per account id, readable after the
/// first unlock and never synced or restored to another device (as `KeychainTokenStore`).
public struct KeychainAccountTokenStore: AccountTokenStore {
    public let service: String

    public init(service: String = "media.sovereign.sovemu.account-token") { self.service = service }

    private func item(_ id: String) -> KeychainItem { KeychainItem(service: service, account: AccountStore.tokenKey(id)) }

    public func load(_ id: String) -> String? { item(id).load() }
    public func save(_ token: String, for id: String) { item(id).save(token) }
    public func remove(_ id: String) { item(id).delete() }
}
#endif

// MARK: - AccountStore

/// What `AccountStore.upsert` did with a new session.
public enum AccountUpsert: Sendable, Equatable {
    case stored(StoredAccount)
    /// A new account that does not fit; nothing changed.
    case refused(AccountRefusal)
}

/// What taking a server off the device removed: each account with its refresh token (for the
/// caller to revoke, on its own server only), and whether the active account was among them.
public struct ServerRemoval: Sendable, Equatable {
    public struct Removed: Sendable, Equatable {
        public let account: StoredAccount
        public let refreshToken: String?
    }

    public let removed: [Removed]
    public let wasActive: Bool
}

/// Every account signed in on this device and which one is active: the list
/// (`StoredAccountCodec`), the active id and each account's device name in `values`, each
/// account's refresh token in `tokens`. Nothing in here is ever logged.
///
/// **A write to an account that is gone is dropped**: a refresh that started before a sign-out
/// lands after it, and must not bring the removed account's token back.
///
/// One `Mutex` covers every call (Android's `@Synchronized`), so each is atomic.
public final class AccountStore: Sendable {
    public static let accountsKey = "accounts"
    public static let activeKey = "active_account"

    public static func tokenKey(_ id: String) -> String { "refresh_token.\(id)" }
    public static func deviceKey(_ id: String) -> String { "named_device.\(id)" }

    private let values: any KeyValue
    private let tokenStore: any AccountTokenStore
    private let newId: @Sendable () -> String

    private struct State {
        /// Nil until first read from `values`.
        var accounts: [StoredAccount]?
        /// Tokens already read, by account id, so a refresh does not ask the Keychain each time.
        var tokens: [String: String] = [:]
    }

    private let state = Mutex(State())

    public init(
        values: any KeyValue, tokens: any AccountTokenStore,
        newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.values = values
        self.tokenStore = tokens
        self.newId = newId
    }

    /// Every stored account, on every server, in the order they were added.
    public func all() -> [StoredAccount] { state.withLock { load(&$0) } }

    public func account(_ id: String) -> StoredAccount? { all().first { $0.id == id } }

    /// The accounts stored for the server at `server`.
    public func accounts(on server: String) -> [StoredAccount] { all().filter { $0.isOn(server) } }

    /// The account the app refreshes, or nil while nobody has been chosen.
    public func activeId() -> String? {
        state.withLock { s in
            _ = load(&s)
            return values.get(Self.activeKey)
        }
    }

    /// The active account, or nil with nobody chosen.
    public func active() -> StoredAccount? { activeId().flatMap(account) }

    /// Makes `id` the active account (or none), stamped as used at `now` (wall clock, ms). An id
    /// that is not stored clears the active account instead.
    public func setActive(_ id: String?, now: Int64) {
        state.withLock { setActive(&$0, id, now: now) }
    }

    /// Stores the session a sign-in just produced: replaces the account with the same `subject`
    /// on `server`, else adds one, unless a new account would not fit (`StoredAccount.refusalFor`),
    /// when nothing changes.
    public func upsert(subject: String, server: String, clientId: String?, userName: String?, now: Int64) -> AccountUpsert {
        state.withLock { upsert(&$0, subject: subject, server: server, clientId: clientId, userName: userName, now: now) }
    }

    /// What a refresh learned: the account's username and the client its rotated token belongs to.
    /// Never its `sub`.
    public func recordRefresh(_ id: String, idToken: IdToken, clientId: String?) {
        state.withLock { s in
            let accounts = load(&s)
            guard var updated = accounts.first(where: { $0.id == id }) else { return }
            let current = updated
            updated.userName = idToken.userName ?? current.userName
            updated.clientId = clientId
            if updated != current { save(&s, accounts.map { $0.id == id ? updated : $0 }) }
        }
    }

    /// Removes one account and its token; the active id goes with it if it was this one.
    public func remove(_ id: String) { removeAll([id]) }

    /// Removes every account in `ids` and their tokens: a server taken off the device.
    public func removeAll(_ ids: some Collection<String>) {
        state.withLock { removeAll(&$0, Set(ids)) }
    }

    /// `id`'s refresh token, or nil when there is none (also when the Keychain no longer has it:
    /// the defaults came back with a restore and this-device-only items did not).
    public func refreshToken(_ id: String) -> String? {
        state.withLock { refreshToken(&$0, id) }
    }

    /// Stores `token` for `id`, only while `id` is still a stored account.
    public func setRefreshToken(_ id: String, _ token: String) {
        state.withLock { setRefreshToken(&$0, id, token) }
    }

    /// The device name last given to `id`'s sign-in on the server (`nameDevice`), if any.
    public func namedDevice(_ id: String) -> String? { state.withLock { _ in values.get(Self.deviceKey(id)) } }

    public func setNamedDevice(_ id: String, _ name: String) {
        state.withLock { s in
            if load(&s).contains(where: { $0.id == id }) { values.put(Self.deviceKey(id), name) }
        }
    }

    // MARK: - Session's account halves

    /// Where a launch lands on `server` (`LaunchAccounts`), as Android's `Session.launch`, without
    /// a token request: no account clears the active one, one is made active (stamped `now`), two
    /// or more leave nobody active for the picker. Also where a sign-out or a change of server
    /// lands.
    public func launch(on server: String, now: Int64) -> LaunchAccounts {
        state.withLock { s in
            let here = load(&s).filter { $0.isOn(server) }
            let decision = LaunchAccounts.decide(here.count)
            setActive(&s, decision == .restore ? here.first?.id : nil, now: now)
            return decision
        }
    }

    /// Keeps the session a sign-in on `server` got, as Android's `Session.signedInWith`: keyed by
    /// the ID token's `sub` and labelled by its `preferred_username`, stored with its refresh
    /// token and made active. Tokens that say nobody signed in, or a new account that does not
    /// fit, are refused and nothing changes: **the caller then revokes `refreshToken`**, and
    /// whoever was signed in stays so.
    public func signedIn(idToken: String?, refreshToken: String, server: String, clientId: String?, now: Int64) -> AccountUpsert {
        let id = IdToken.read(idToken)
        guard let subject = id.subject else { return .refused(.noIdentity) }
        return state.withLock { s in
            let result = upsert(&s, subject: subject, server: server, clientId: clientId, userName: id.userName, now: now)
            if case .stored(let account) = result {
                setRefreshToken(&s, account.id, refreshToken)
                setActive(&s, account.id, now: now)
            }
            return result
        }
    }

    /// Takes the server at `address` off the device (*Choose a server*), as Android's
    /// `Session.removeServer`: every account on it goes, with its token. What went comes back
    /// with each token, for the caller to revoke while that server is the current one.
    public func removeServer(_ address: String) -> ServerRemoval {
        state.withLock { s in
            let doomed = load(&s).filter { $0.isOn(address) }
            guard !doomed.isEmpty else { return ServerRemoval(removed: [], wasActive: false) }
            let removed = doomed.map { ServerRemoval.Removed(account: $0, refreshToken: refreshToken(&s, $0.id)) }
            let active = values.get(Self.activeKey)
            let wasActive = doomed.contains { $0.id == active }
            removeAll(&s, Set(doomed.map(\.id)))
            return ServerRemoval(removed: removed, wasActive: wasActive)
        }
    }

    // MARK: - Under the lock

    private func load(_ s: inout State) -> [StoredAccount] {
        if let accounts = s.accounts { return accounts }
        let accounts = StoredAccountCodec.decode(values.get(Self.accountsKey))
        s.accounts = accounts
        return accounts
    }

    private func save(_ s: inout State, _ accounts: [StoredAccount]) {
        values.put(Self.accountsKey, StoredAccountCodec.encode(accounts))
        s.accounts = accounts
    }

    private func setActive(_ s: inout State, _ id: String?, now: Int64) {
        let accounts = load(&s)
        guard let id, accounts.contains(where: { $0.id == id }) else {
            values.remove(Self.activeKey)
            return
        }
        values.put(Self.activeKey, id)
        save(&s, accounts.map { a in
            guard a.id == id else { return a }
            var used = a
            used.lastUsedAt = now
            return used
        })
    }

    private func upsert(
        _ s: inout State, subject: String, server: String, clientId: String?, userName: String?, now: Int64
    ) -> AccountUpsert {
        var accounts = load(&s)
        let stored: StoredAccount
        if let index = accounts.firstIndex(where: { $0.subject == subject && $0.isOn(server) }) {
            // A new sign-in is a new device on the server, with no name yet.
            values.remove(Self.deviceKey(accounts[index].id))
            var account = accounts[index]
            account.server = server
            account.clientId = clientId
            account.userName = userName ?? account.userName
            account.lastUsedAt = now
            accounts[index] = account
            stored = account
        } else {
            if let refusal = StoredAccount.refusalFor(accounts, server: server) { return .refused(refusal) }
            stored = StoredAccount(
                id: newId(), subject: subject, server: server, clientId: clientId, userName: userName, lastUsedAt: now)
            accounts.append(stored)
        }
        save(&s, accounts)
        return .stored(stored)
    }

    private func removeAll(_ s: inout State, _ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        save(&s, load(&s).filter { !ids.contains($0.id) })
        for id in ids {
            tokenStore.remove(id)
            values.remove(Self.deviceKey(id))
            s.tokens[id] = nil
            if values.get(Self.activeKey) == id { values.remove(Self.activeKey) }
        }
    }

    private func refreshToken(_ s: inout State, _ id: String) -> String? {
        _ = load(&s)
        if let token = s.tokens[id] { return token }
        let token = tokenStore.load(id)
        if let token { s.tokens[id] = token }
        return token
    }

    private func setRefreshToken(_ s: inout State, _ id: String, _ token: String) {
        guard load(&s).contains(where: { $0.id == id }) else { return }
        tokenStore.save(token, for: id)
        s.tokens[id] = token
    }
}
