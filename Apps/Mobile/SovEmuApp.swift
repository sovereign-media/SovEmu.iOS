import SwiftUI
import SovEmuKit

@main
struct SovEmuApp: App {
    @State private var model: AppModel
    @State private var library: Library
    @State private var settings = AppSettings()

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _library = State(initialValue: Library(api: { [weak model] in model?.api }, signedOut: { [weak model] in model?.signedIn = false }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(library)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Sov.accent)
        }
    }
}

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

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var phase
    @State private var checked = false
    @State private var playing: PlayRequest?
    @State private var idle = IdleWatcher()
    @State private var screensaver = false
    @State private var music = MenuMusic()

    var body: some View {
        ZStack {
            if !checked {
                ProgressView()
            } else if !model.signedIn {
                ConnectView()
            } else {
                MainView()
                    .environment(\.playGame, PlayAction { system, game, start in playing = PlayRequest(system: system, game: game, start: start) })
            }
            // A CRT look over the menus; never over a game, whose stream is the console's own picture.
            if settings.scanlines && playing == nil { Scanlines() }
            if screensaver && model.signedIn && playing == nil {
                ScreensaverView {
                    screensaver = false
                    idle.touched()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: screensaver)
        .fullScreenCover(item: $playing) { request in
            PlayerView(system: request.system, game: request.game, start: request.start) {
                playing = nil
            }
            .onDisappear { library.played(request.system.id) }
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
            if model.signedIn {
                library.refresh()
                await model.nameDevice()
            }
            idle.install()
        }
        .onChange(of: model.signedIn) { _, signedIn in
            library.clear()
            if signedIn {
                library.refresh()
                Task { await model.nameDevice() }
            }
        }
        // The screensaver, after the chosen minutes without input in the menus.
        .task(id: settings.screensaverMinutes) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                let minutes = settings.screensaverMinutes
                if minutes > 0, model.signedIn, playing == nil, !screensaver,
                   Date().timeIntervalSince(idle.lastInput) >= Double(minutes * 60) {
                    screensaver = true
                }
            }
        }
        .onAppear(perform: update)
        .onChange(of: playing == nil) { update() }
        .onChange(of: screensaver) { update() }
        .onChange(of: phase) { update() }
        .onChange(of: settings.music) { update() }
        .onChange(of: settings.screensaverMinutes) { update() }
    }

    /// Music in the menus (a game, and the screensaver's videos, have their own sound), and the
    /// screen kept awake while a game plays, or in the menus while a screensaver will come.
    private func update() {
        let menus = playing == nil
        music.play(settings.music && menus && !screensaver && phase == .active)
        UIApplication.shared.isIdleTimerDisabled = !menus || (settings.screensaverMinutes > 0 && model.signedIn)
        if menus { idle.touched() }
    }
}

enum AppTab: Hashable {
    case home, search, systems, account
}

/// The signed-in app: Home, Search, Systems and the account, as the other clients' navigation
/// (tabs on an iPhone, a sidebar on an iPad), each tab keeping its own way back.
struct MainView: View {
    @Environment(Library.self) private var library
    @State private var tab = AppTab.home
    @State private var home: [Route] = []
    @State private var search: [Route] = []
    @State private var systems: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $home) { HomeView(path: $home).routes() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack(path: $search) { SearchView().routes() }
            }
            Tab("Systems", systemImage: "gamecontroller", value: AppTab.systems) {
                NavigationStack(path: $systems) { SystemsList().routes() }
            }
            Tab(library.user?.username ?? "Account", systemImage: "person.crop.circle", value: AppTab.account) {
                NavigationStack { AccountView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

extension View {
    /// Where a tab's links go.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .system(let system, let open): SystemView(system: system, openFirst: open)
            }
        }
    }
}

extension SystemSummary {
    var accent: Color {
        let (r, g, b) = rgb
        return Color(red: r, green: g, blue: b)
    }
}
