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
                .environment(library)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Sov.accent)
        }
    }
}

/// The signed-in app, as SovEmu.Android's TV app (`Nav.kt`): a dock down the left (Home, Search,
/// Systems, the account) beside the page, each tab keeping its own way back. The dock shows icons
/// only, and opens to show their names while it has the focus; Back from a tab's first page goes
/// to the dock.
struct MainView: View {
    @Environment(Library.self) private var library
    @State private var tab = TVTab.home
    @State private var home: [Route] = []
    @State private var search: [Route] = []
    @State private var systems: [Route] = []
    @FocusState private var docked: TVTab?
    @Namespace private var scope

    fileprivate enum TVTab: Hashable, CaseIterable {
        case home, search, systems, account

        var symbol: String {
            switch self {
            case .home: "house"
            case .search: "magnifyingglass"
            case .systems: "gamecontroller"
            case .account: "person.crop.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            dock
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
                // The page has the focus at first, as on SovEmu.Android's TV app: the dock
                // opens only when it is gone to.
                .prefersDefaultFocus(in: scope)
        }
        .focusScope(scope)
        .background(Sov.surface.ignoresSafeArea())
    }

    private func name(_ tab: TVTab) -> String {
        switch tab {
        case .home: "Home"
        case .search: "Search"
        case .systems: "Systems"
        case .account: library.user?.username ?? "Account"
        }
    }

    private var dock: some View {
        let open = docked != nil
        return VStack(alignment: .leading, spacing: 14) {
            Image("SovEmuMark").resizable().scaledToFit().frame(width: 44, height: 44)
                .foregroundStyle(Sov.accent)
                .padding(.leading, 18).padding(.bottom, 40)
            ForEach([TVTab.home, .search, .systems], id: \.self) { item($0, open: open) }
            Spacer()
            item(.account, open: open)
        }
        .padding(.vertical, 50)
        .padding(.horizontal, 20)
        .frame(width: open ? 340 : 124, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(open ? 0.55 : 0.25).ignoresSafeArea())
        .focusSection()
        .animation(.easeOut(duration: 0.2), value: open)
    }

    private func item(_ item: TVTab, open: Bool) -> some View {
        Button {
            tab = item
        } label: {
            HStack(spacing: 20) {
                Image(systemName: item.symbol).font(.title3).frame(width: 40)
                if open { Text(name(item)).lineLimit(1) }
            }
            .foregroundStyle(item == tab && !open ? Sov.accent : .primary)
        }
        .focused($docked, equals: item)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .home:
            NavigationStack(path: $home) { HomeView(path: $home).routes().backToDock(home.isEmpty) { docked = .home } }
        case .search:
            NavigationStack(path: $search) { SearchView().routes().backToDock(search.isEmpty) { docked = .search } }
        case .systems:
            NavigationStack(path: $systems) { SystemsList().routes().backToDock(systems.isEmpty) { docked = .systems } }
        case .account:
            NavigationStack { TVAccountView().backToDock(true) { docked = .account } }
        }
    }
}

private extension View {
    /// Back on a tab's first page goes to the dock (where a second Back leaves the app), as on
    /// SovEmu.Android's TV app.
    @ViewBuilder func backToDock(_ atRoot: Bool, _ toDock: @escaping () -> Void) -> some View {
        if atRoot { onExitCommand(perform: toDock) } else { self }
    }
}

extension View {
    /// Where a tab's links go.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .system(let system, let open): TVSystemView(system: system, openFirst: open)
            }
        }
    }
}
