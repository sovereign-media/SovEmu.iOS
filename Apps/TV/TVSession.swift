// The TV's accounts: several signed in on several servers, one active, as SovEmu.Android's
// `core/Session.kt` (and its launch rule, `Launch.kt`). The account logic is SovEmuKit's
// (`AccountStore`, `ServerChooser`, `IdlePicker`); this only adds the tokens and the client. The
// shared screens keep reading `AppModel`: this session drives it (the server, the active
// account's client, signed in or not).
import Foundation
import SovEmuKit
import Synchronization
import SwiftUI

/// One Android dp in tvOS points: Android TV lays out 1280 dp across, tvOS 1920 points.
let launchDp: CGFloat = 1.5

/// The page of the launch screens, as Android's `LaunchPage`.
enum LaunchPage: Hashable {
    /// *Who's watching?*
    case picker
    /// *Choose a server*.
    case servers
    /// The proxy headers.
    case headers
    /// The sign-in form: `addUser` heads it *Add a user*; `username` and `expired` after a
    /// sign-in ended; `newServer` is *Add a server*, which puts `returnTo` back on Back.
    case signIn(addUser: Bool = false, username: String = "", expired: Bool = false, newServer: Bool = false, returnTo: String? = nil)
}

/// The account store's refresh token for one account, as a `TokenClient` keeps its token: the
/// account is fixed when the client is made, so a refresh that lands after a switch writes to the
/// account it began for (and `AccountStore` drops a write to one that is gone). Clearing it (a
/// sign-out, or a token the server refused) removes the account.
private struct AccountTokens: RefreshTokenStore {
    let store: AccountStore
    let id: String?

    func load() -> String? { id.flatMap(store.refreshToken) }
    func save(_ token: String) { if let id { store.setRefreshToken(id, token) } }
    func clear() { if let id { store.remove(id) } }
    func loadClientId() -> String? { id.flatMap(store.account)?.clientId }
    func saveClientId(_ clientId: String?) {
        if let id { store.recordRefresh(id, idToken: .empty, clientId: clientId) }
    }
}

/// The proxy headers, read on every request from any thread.
private final class HeaderBox: Sendable {
    let value = Mutex<[CustomHeader]>([])
}

/// A sign-in under way on the form: a client of its own, whose tokens stay in memory until the
/// session keeps them for an account (`TVSession.signedIn`).
struct PendingSignIn {
    let api: SovEmuAPI
    fileprivate let tokens: MemoryTokenStore
}

@MainActor
@Observable
final class TVSession {
    /// What the shared screens read: the server, the active account's client, signed in or not.
    let model: AppModel
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let headerBox: HeaderBox

    /// Every account on the device, on every server, as stored.
    private(set) var accounts: [StoredAccount] = []
    /// The account signed in now, if any.
    private(set) var current: StoredAccount?
    /// The account whose sign-in the server just ended, for the sign-in form to name.
    private(set) var lastExpired: StoredAccount?
    /// The launch screens over the signed-in app: *Change user or server*.
    var overApp = false
    /// Between one account and the next, while the app is made again for it.
    private(set) var switching = false
    /// Bumped at each landing, so the launch screens start again from `startPages`.
    private(set) var landings = 0
    @ObservationIgnored private var backgroundedAt: Int64?

    var headers: [CustomHeader] {
        didSet {
            headers = CustomHeaderRules.sanitize(headers)
            headerBox.value.withLock { $0 = headers }
            UserDefaults.standard.set(CustomHeaderRules.encode(headers), forKey: Self.headersKey)
        }
    }

    var secureOnly: Bool {
        didSet { UserDefaults.standard.set(secureOnly, forKey: Self.secureOnlyKey) }
    }

    private static let headersKey = "customHeaders"
    private static let secureOnlyKey = "secureOnly"

    init(defaults: UserDefaults = .standard) {
        let store = AccountStore(values: UserDefaultsKeyValue(defaults, prefix: "tv."), tokens: KeychainAccountTokenStore())
        let box = HeaderBox()
        let saved = CustomHeaderRules.decode(defaults.string(forKey: Self.headersKey))
        box.value.withLock { $0 = saved }
        self.store = store
        headerBox = box
        headers = saved
        secureOnly = defaults.object(forKey: Self.secureOnlyKey) as? Bool ?? true
        model = AppModel(
            // Only the active account's token, and only to its own server.
            tokenStore: { url in
                AccountTokens(store: store, id: store.active().flatMap { $0.isOn(url.absoluteString) ? $0.id : nil })
            },
            customHeaders: { box.value.withLock { $0 } },
            deviceName: (
                { store.activeId().flatMap(store.namedDevice) },
                { name in if let name, let id = store.activeId() { store.setNamedDevice(id, name) } }))
        model.onSignedOut = { [weak self] refused in self?.endedOnServer(refused: refused) }
        // Where the app opens, without a token request: the sign-in form, the one account here,
        // or *Who's watching?*.
        relaunch()
    }

    // MARK: - What the screens read

    /// The accounts stored for the server in use.
    var accountsHere: [StoredAccount] { accounts.filter { $0.isOn(model.serverURL) } }

    /// The servers the device holds accounts for, the one in use marked.
    var servers: [KnownServer] { KnownServers.list(accounts, current: model.serverURL) }

    /// Where the launch screens open now.
    func startPages() -> [LaunchPage] {
        if let ended = lastExpired {
            let form = LaunchPage.signIn(username: ended.userName ?? "", expired: true)
            return accountsHere.isEmpty ? [form] : [.picker, form]
        }
        if overApp || (!accountsHere.isEmpty && !model.signedIn) { return [.picker] }
        return [.signIn()]
    }

    // MARK: - For the account menu

    /// *Change user or server*: *Who's watching?* over the app, the account signed in now marked;
    /// choosing it, or Back, goes back to the app as it was.
    func changeUserOrServer() {
        overApp = true
    }

    /// *Sign out*: the active account only (its token revoked on its server); every other
    /// account stays. Lands as a launch does: the sign-in form, the one account left, or the
    /// picker.
    func signOut() async {
        let api = model.api
        // Revokes the token and clears it, which takes the account off the device.
        await api?.auth?.signOut()
        if let id = current?.id { store.remove(id) }
        lastExpired = nil
        refresh()
        relaunch()
    }

    // MARK: - Choosing

    /// Decides where the app opens for the server in use, as Android's `Session.launch`.
    @discardableResult
    func relaunch() -> LaunchAccounts {
        let decision = store.launch(on: model.serverURL, now: Self.wallMs)
        refresh()
        show(decision == .restore ? store.active() : nil, anew: false)
        return decision
    }

    /// Makes `account` the one signed in: the picker's choice. The one signed in now, chosen
    /// from over the app, goes back to it unchanged.
    func choose(_ account: StoredAccount) {
        if account.id == current?.id && model.signedIn {
            overApp = false
            return
        }
        store.setActive(account.id, now: Self.wallMs)
        lastExpired = nil
        refresh()
        show(store.active(), anew: false)
    }

    /// Nobody active and the picker up, nobody signed out: the idle picker.
    func pick() {
        guard !accountsHere.isEmpty else {
            relaunch()
            return
        }
        store.setActive(nil, now: Self.wallMs)
        refresh()
        show(nil, anew: false)
    }

    // MARK: - Signing in

    /// A client to sign in with at the server in use, its tokens kept apart until `signedIn`.
    func pendingSignIn() -> PendingSignIn? {
        guard let url = URL(string: model.serverURL), url.host() != nil else { return nil }
        let tokens = MemoryTokenStore()
        let box = headerBox
        let headers: @Sendable () -> [CustomHeader] = { box.value.withLock { $0 } }
        let auth = TokenClient(
            baseURL: url, endpoints: model.bootstrap?.endpoints(relativeTo: url), store: tokens, customHeaders: headers)
        return PendingSignIn(api: SovEmuAPI(baseURL: url, auth: auth, customHeaders: headers), tokens: tokens)
    }

    /// Keeps what `pending` signed in to, as Android's `Session.signedInWith`: keyed by the ID
    /// token's `sub` (the same person on this server replaces their session), refused past the
    /// caps (the new token revoked, whoever was signed in stays so), then made active.
    func signedIn(_ pending: PendingSignIn) async throws {
        guard let refreshToken = pending.tokens.load() else {
            throw AuthError(status: 200, code: "invalid_response", message: "The server granted no refresh token.")
        }
        let idToken = await pending.api.auth?.idToken
        let result = store.signedIn(
            idToken: idToken, refreshToken: refreshToken, server: model.serverURL,
            clientId: pending.tokens.loadClientId(), now: Self.wallMs)
        switch result {
        case .stored(let account):
            lastExpired = nil
            refresh()
            show(account, anew: true)
        case .refused(let refusal):
            await pending.api.signOut()
            throw refusal.error
        }
    }

    // MARK: - The idle picker

    /// The app went to the background, or came back: after an hour away with two or more
    /// accounts here, *Who's watching?* comes back (never over a game).
    func scenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Self.monotonicMs
        case .active:
            let show = IdlePicker.shouldShow(
                backgroundedAt: backgroundedAt, now: Self.monotonicMs, accounts: accountsHere.count, playing: model.playing)
            backgroundedAt = nil
            if show {
                overApp = false
                pick()
            }
        default:
            break
        }
    }

    // MARK: - Landing

    /// Shows `account`'s app, or the launch screens with nobody (`nil`). A switch from one
    /// account to another goes through signed-out for a moment, so the app is made again for the
    /// next account (nothing of the last one's stays on screen).
    private func show(_ account: StoredAccount?, anew: Bool) {
        current = account
        overApp = false
        model.remakeClient()
        landings += 1
        guard account != nil else {
            model.signedIn = false
            return
        }
        let finish = { [model] in anew ? model.signedInAnew() : (model.signedIn = true) }
        guard model.signedIn else { return finish() }
        switching = true
        model.signedIn = false
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            switching = false
            finish()
        }
    }

    /// The server ended the active account's sign-in (`refused`: its token refused, and the
    /// account already gone with it), or the app signed it out.
    private func endedOnServer(refused: Bool) {
        if refused { lastExpired = current }
        if let id = current?.id { store.remove(id) }
        current = nil
        refresh()
        if refused {
            store.setActive(nil, now: Self.wallMs)
            overApp = false
            landings += 1
        } else {
            relaunch()
        }
    }

    private func refresh() {
        accounts = store.all()
    }

    private static var wallMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// A monotonic clock that counts deep sleep, in ms.
    private static var monotonicMs: Int64 { Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }
}

// MARK: - Choose a server

extension TVSession: ServerService, AccountSession {
    nonisolated func server() async -> String { await MainActor.run { model.serverURL } }

    nonisolated func setServer(_ address: String) async {
        await MainActor.run { model.serverURL = address }
    }

    nonisolated func bootstrap(at address: String) async throws -> BootstrapConfig {
        await MainActor.run { model.serverURL = address }
        return try await model.refreshBootstrap()
    }

    nonisolated func launch() async -> LaunchAccounts {
        await MainActor.run { relaunch() }
    }

    /// Signs out everyone on `address`, each token revoked (only while that server is the one
    /// in use: a token goes only to its own server), without waiting.
    @discardableResult
    nonisolated func removeServer(_ address: String) async -> Bool {
        await MainActor.run { removeServerNow(address) }
    }

    private func removeServerNow(_ address: String) -> Bool {
        let removal = store.removeServer(address)
        if StoredAccount.sameServer(address, model.serverURL), let url = URL(string: model.serverURL) {
            let endpoints = model.bootstrap?.endpoints(relativeTo: url)
            let box = headerBox
            for gone in removal.removed {
                guard let token = gone.refreshToken else { continue }
                let tokens = MemoryTokenStore(token)
                tokens.saveClientId(gone.account.clientId)
                let client = TokenClient(
                    baseURL: url, endpoints: endpoints, store: tokens, customHeaders: { box.value.withLock { $0 } })
                Task { await client.signOut() }
            }
        }
        if removal.wasActive {
            current = nil
            model.signedIn = false
        }
        refresh()
        return removal.wasActive
    }
}
