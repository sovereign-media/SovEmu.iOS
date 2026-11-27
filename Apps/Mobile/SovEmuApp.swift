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
                .environment(\.api, model.api)
                .environment(library)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Sov.accent)
        }
    }
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
