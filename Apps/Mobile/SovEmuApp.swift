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

/// The server address (kept across launches) and the API client for it. Signed in means a
/// refresh token for that server is in the Keychain; the access token lives in the client.
@Observable
final class AppModel {
    var serverURL: String = UserDefaults.standard.string(forKey: "server") ?? "" {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "server")
            if serverURL != oldValue { api = makeAPI() }
        }
    }
    var signedIn = false
    /// One client per server address, so its token refreshes are shared by every screen.
    @ObservationIgnored private(set) var api: SovEmuAPI?

    init() {
        // Before tokens the server signed in with a cookie; it means nothing now.
        SovEmuAPI.clearLegacySessionCookie()
        api = makeAPI()
        signedIn = api?.isSignedIn ?? false
    }

    private func makeAPI() -> SovEmuAPI? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        // The server refused the refresh token (expired or revoked): back to the sign-in screen.
        let auth = TokenClient(baseURL: url, store: KeychainTokenStore(server: url), onSignedOut: { [weak self] in
            Task { @MainActor in self?.signedIn = false }
        })
        return SovEmuAPI(baseURL: url, auth: auth)
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
