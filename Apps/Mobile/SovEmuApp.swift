import SwiftUI
import SovEmuKit

@main
struct SovEmuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

/// The server address and its `bootstrapConfig` (both kept across launches) and the API client
/// for it. Signed in means a refresh token for that server is in the Keychain; the access token
/// lives in the client.
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
        // Before tokens the server signed in with a cookie; it means nothing now.
        SovEmuAPI.clearLegacySessionCookie()
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

enum Route: Hashable {
    case games(SystemSummary)
    case play(SystemSummary, Game)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var checked = false

    var body: some View {
        Group {
            if !checked {
                ProgressView()
            } else if !model.signedIn {
                ConnectView()
            } else {
                NavigationStack(path: $path) {
                    SystemsView(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .games(let system):
                                GamesView(system: system, path: $path)
                            case .play(let system, let game):
                                PlayerView(system: system, game: game) { path.removeLast() }
                                    .toolbar(.hidden, for: .navigationBar)
                            }
                        }
                }
            }
        }
        .task {
            // Ask how to sign in first, each launch the server answers; offline, the stored
            // answer stands.
            if model.api != nil { _ = try? await model.refreshBootstrap() }
            // A stored refresh token is a sign-in; asking who we are refreshes it, and ends it
            // if the server no longer honours it. Offline, stay signed in: the next screen says
            // what is wrong.
            if let api = model.api, api.isSignedIn {
                do {
                    if try await api.status().user == nil { await model.signOut() }
                } catch let error as APIError where error.isUnauthenticated {
                    model.signedIn = false
                } catch {}
            }
            checked = true
        }
    }
}

extension SystemSummary {
    var accent: Color {
        let (r, g, b) = rgb
        return Color(red: r, green: g, blue: b)
    }
}
