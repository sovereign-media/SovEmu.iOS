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
