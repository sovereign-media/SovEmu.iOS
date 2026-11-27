// The Apple TV app: SovEmu.Android's TV app (`:apps:androidtv`, `:common:feature-tv`) drawn
// the tvOS way, over SovEmuKit and Apps/Shared (the same screens as the iPhone and iPad app
// wherever a TV shows them alike). Its own here: sign-in, the sidebar and the account menu.
import SwiftUI
import SovEmuKit

@main
struct SovEmuTVApp: App {
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

/// The signed-in app: Home, Search, Systems and the account in tvOS's sidebar, where
/// SovEmu.Android's TV app has its dock, each keeping its own way back.
struct MainView: View {
    @Environment(Library.self) private var library
    @State private var tab = TVTab.home
    @State private var home: [Route] = []
    @State private var search: [Route] = []
    @State private var systems: [Route] = []

    private enum TVTab: Hashable {
        case home, search, systems, account
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: TVTab.home) {
                NavigationStack(path: $home) { HomeView(path: $home).routes() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: TVTab.search, role: .search) {
                NavigationStack(path: $search) { SearchView().routes() }
            }
            Tab("Systems", systemImage: "gamecontroller", value: TVTab.systems) {
                NavigationStack(path: $systems) { SystemsList().routes() }
            }
            Tab(library.user?.username ?? "Account", systemImage: "person.crop.circle", value: TVTab.account) {
                NavigationStack { TVAccountView() }
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
