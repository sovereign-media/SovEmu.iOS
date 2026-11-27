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

    init() {
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

    private func makeAPI() -> SovEmuAPI? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.host() != nil else { return nil }
        // The server refused the refresh token (expired or revoked): back to the sign-in screen.
        let endpoints = bootstrap?.endpoints(relativeTo: url)
        let auth = TokenClient(baseURL: url, endpoints: endpoints, store: KeychainTokenStore(server: url), onSignedOut: { [weak self] in
            Task { @MainActor in self?.signedIn = false }
        })
        let api = SovEmuAPI(baseURL: url, auth: auth)
        ClientEvents.api = api
        return api
    }

    /// The device name last given to this sign-in (`nameDevice`); cleared by a new sign-in.
    private static let namedDeviceKey = "namedDevice"

    /// A new sign-in on the server: it has no device name yet.
    func signedInAnew() {
        UserDefaults.standard.removeObject(forKey: Self.namedDeviceKey)
        signedIn = true
    }

    /// Names this sign-in's device on the server once (and again after an update changes the
    /// version), for the admin's Devices page. Best effort: unnamed, it only shows as "App".
    func nameDevice() async {
        let name = ClientEvents.deviceName
        guard let api, UserDefaults.standard.string(forKey: Self.namedDeviceKey) != name else { return }
        if (try? await api.nameDevice(name)) != nil {
            UserDefaults.standard.set(name, forKey: Self.namedDeviceKey)
        }
    }

    func signOut() async {
        await api?.signOut()
        signedIn = false
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
