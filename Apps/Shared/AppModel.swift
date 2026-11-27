// The signed-in server and how to start a game: what both apps' roots hold. SovEmu.Android's
// `Session` (one account here; the TV's accounts are ported from `AccountStore`) and its
// player route.
import SwiftUI
import SovEmuKit

/// The server address and its `bootstrapConfig` (both kept across launches) and the API client
/// for it. Signed in means a refresh token for that server is in the Keychain; the access token
/// lives in the client.
@MainActor
@Observable
final class AppModel {
    var serverURL: String = UserDefaults.standard.string(forKey: "server") ?? "" {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "server")
            if serverURL != oldValue {
                bootstrap = nil
                api = makeAPI()
            }
        }
    }
    var signedIn = false
    /// A game is on screen (set by `RootView`): the TV's idle picker never comes over one.
    var playing = false
    /// How to sign in at `serverURL`: the server's last answer, kept so that refreshing a token
    /// works on a start without the server, and asked again whenever it can be.
    private(set) var bootstrap: BootstrapConfig?
    /// One client per server address, so its token refreshes are shared by every screen.
    @ObservationIgnored private(set) var api: SovEmuAPI?

    /// What is stored: the answer with the address it came from.
    private struct SavedBootstrap: Codable {
        let server: String
        let config: BootstrapConfig
    }
    private static let bootstrapKey = "bootstrap"

    /// Where a client keeps its refresh token: the phone's one sign-in per server
    /// (`KeychainTokenStore`), or on the TV the active account's (`TVSession`).
    @ObservationIgnored private let tokenStore: (URL) -> any RefreshTokenStore
    /// The person's proxy headers (`CustomHeaderRules`), sent to the server only.
    @ObservationIgnored private let customHeaders: @Sendable () -> [CustomHeader]
    /// Told when a sign-in ends: `refused` when the server refused the refresh token, else a
    /// sign-out. The TV's session lands where its accounts say; the phone needs nothing.
    @ObservationIgnored var onSignedOut: ((_ refused: Bool) -> Void)?
    /// The device name last given to the signed-in session (`nameDevice`): the phone's in the
    /// defaults, the TV's per account.
    @ObservationIgnored private let deviceName: (get: () -> String?, set: (String?) -> Void)

    init(
        tokenStore: @escaping (URL) -> any RefreshTokenStore = { KeychainTokenStore(server: $0) },
        customHeaders: @escaping @Sendable () -> [CustomHeader] = { [] },
        deviceName: (get: () -> String?, set: (String?) -> Void) = (
            { UserDefaults.standard.string(forKey: AppModel.namedDeviceKey) },
            { UserDefaults.standard.set($0, forKey: AppModel.namedDeviceKey) })
    ) {
        self.tokenStore = tokenStore
        self.customHeaders = customHeaders
        self.deviceName = deviceName
        if let data = UserDefaults.standard.data(forKey: Self.bootstrapKey),
           let saved = try? JSONDecoder().decode(SavedBootstrap.self, from: data), saved.server == serverURL {
            bootstrap = saved.config
        }
        api = makeAPI()
        signedIn = api?.isSignedIn ?? false
    }

    /// Asks the server how to sign in (also the check that a SovEmu server answers there), and
    /// keeps the answer.
    @discardableResult
    func refreshBootstrap() async throws -> BootstrapConfig {
        guard let api else { throw URLError(.badURL) }
        let config = try await api.bootstrap()
        bootstrap = config
        UserDefaults.standard.set(try? JSONEncoder().encode(SavedBootstrap(server: serverURL, config: config)), forKey: Self.bootstrapKey)
        return config
    }

    /// A new client for the same address: the TV's active account changed.
    func remakeClient() {
        api = makeAPI()
    }

    private func makeAPI() -> SovEmuAPI? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.host() != nil else { return nil }
        // The server refused the refresh token (expired or revoked): back to the sign-in screen.
        let endpoints = bootstrap?.endpoints(relativeTo: url)
        let auth = TokenClient(baseURL: url, endpoints: endpoints, store: tokenStore(url), onSignedOut: { [weak self] in
            Task { @MainActor in
                self?.signedIn = false
                self?.onSignedOut?(true)
            }
        }, customHeaders: customHeaders)
        let api = SovEmuAPI(baseURL: url, auth: auth, customHeaders: customHeaders)
        ClientEvents.api = api
        return api
    }

    /// The device name last given to this sign-in (`nameDevice`); cleared by a new sign-in.
    nonisolated static let namedDeviceKey = "namedDevice"

    /// A new sign-in on the server: it has no device name yet.
    func signedInAnew() {
        deviceName.set(nil)
        signedIn = true
    }

    /// Names this sign-in's device on the server once (and again after an update changes the
    /// version), for the admin's Devices page. Best effort: unnamed, it only shows as "App".
    func nameDevice() async {
        let name = ClientEvents.deviceName
        guard let api, deviceName.get() != name else { return }
        if (try? await api.nameDevice(name)) != nil {
            deviceName.set(name)
        }
    }

    func signOut() async {
        await api?.signOut()
        signedIn = false
        onSignedOut?(false)
    }
}

/// A place inside a tab.
enum Route: Hashable {
    /// A system's games, with a game's panel open (`open`) when it came from Home or Search.
    case system(SystemSummary, open: Int64?)
}

/// A game to play, and how to start it.
struct PlayRequest: Identifiable {
    let id = UUID()
    let system: SystemSummary
    let game: Game
    let start: Start
}

/// Starts a game from anywhere: `play(system, game, start)`.
struct PlayAction {
    var action: (SystemSummary, Game, Start) -> Void = { _, _, _ in }

    func callAsFunction(_ system: SystemSummary, _ game: Game, _ start: Start) { action(system, game, start) }
}

extension EnvironmentValues {
    @Entry var playGame = PlayAction()
}
