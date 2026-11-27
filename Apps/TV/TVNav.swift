// The signed-in TV app's frame, as SovEmu.Android's TV app (`Nav.kt`, after the web's SideNav):
// the wordmark at the top left, and a floating dock on the left edge, icons at rest and labelled
// pills while it has the focus: Home, Search, Systems (a menu of the systems with games, under
// their makers) and the account (a menu of the app's settings, changing user or server, and
// signing out). Sizes are Android TV's in dp, times `dp` (Android lays a TV out on 1280 dp,
// the web client at 150%: 1.5 points each on a 1920-point screen).
import SwiftUI
import SovEmuKit

/// Points per Android dp on a TV.
let dp: CGFloat = 1.5

/// Which section a page belongs to, lit in the dock.
enum TVSection: Hashable {
    case home, search, systems
}

/// A dock entry, for the focus.
private enum DockEntry: Hashable {
    case home, search, systems, account
}

/// The menu open beside the dock.
private enum DockMenu {
    case systems, account
}

struct MainView: View {
    @Environment(Library.self) private var library
    @Environment(\.api) private var api
    /// The admin's background behind every screen (Android TV's `NavFrame`); none is the surface.
    @State private var background: String?
    @State private var section = TVSection.home
    @State private var home: [Route] = []
    @State private var search: [Route] = []
    /// The system the Systems section shows, chosen from its menu, and the way back inside it.
    @State private var system: SystemSummary?
    @State private var systems: [Route] = []
    @State private var menu: DockMenu?
    @FocusState private var docked: DockEntry?
    @Namespace private var scope

    var body: some View {
        ZStack(alignment: .topLeading) {
            Sov.surface.ignoresSafeArea()
            RemoteImage(path: background).ignoresSafeArea()
            page
                .padding(.leading, 64 * dp)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
                .prefersDefaultFocus(in: scope)
                .disabled(menu != nil)
            Wordmark().padding(16 * dp)
            dock
                .padding(.leading, 10 * dp)
                .frame(maxHeight: .infinity)
                .disabled(menu != nil)
            if let menu { menuPanel(menu) }
        }
        .focusScope(scope)
        .ignoresSafeArea()
        .task(id: api?.baseURL) {
            // Without a background the surface shows, as when the admin chose none: nothing to report.
            background = try? await api?.background()
        }
    }

    // MARK: - Pages

    @ViewBuilder private var page: some View {
        switch section {
        case .home:
            NavigationStack(path: $home) { TVHomeView(path: $home).routes().backToDock(home.isEmpty) { docked = .home } }
        case .search:
            NavigationStack(path: $search) { SearchView().routes().backToDock(search.isEmpty) { docked = .search } }
        case .systems:
            NavigationStack(path: $systems) {
                Group {
                    if let system { SystemView(system: system, openFirst: nil) } else { Color.clear }
                }
                .routes()
                .backToDock(systems.isEmpty) { docked = .systems }
            }
            .id(system?.id)
        }
    }

    // MARK: - The dock

    private var dock: some View {
        let open = docked != nil
        return VStack(spacing: 4 * dp) {
            entry(.home, symbol: "house", label: "Home", current: section == .home) { go(.home) }
            entry(.search, symbol: "magnifyingglass", label: "Search", current: section == .search) { go(.search) }
            entry(.systems, symbol: "gamecontroller", label: "Systems", current: section == .systems) { menu = .systems }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1 * dp).padding(.horizontal, 8 * dp).padding(.vertical, 4 * dp)
            // Always there, signed in or not: signing out is the way to another server.
            let name = library.user?.username
            entry(.account, symbol: nil, avatar: name.map(Self.initials), label: name ?? "Account", current: false) { menu = .account }
        }
        .frame(width: open ? 192 * dp : 44 * dp, alignment: .leading)
        .padding(2 * dp)
        .background(Sov.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 24 * dp))
        .overlay(RoundedRectangle(cornerRadius: 24 * dp).stroke(.white.opacity(0.1), lineWidth: 1 * dp))
        .focusSection()
        .animation(.easeOut(duration: 0.2), value: open)
    }

    private func entry(
        _ item: DockEntry, symbol: String?, avatar: String? = nil, label: String, current: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DockLabel(symbol: symbol, avatar: avatar, label: label, current: current, open: docked != nil)
        }
        .buttonStyle(DockButtonStyle(current: current))
        .focused($docked, equals: item)
        .accessibilityLabel(label)
    }

    private func go(_ to: TVSection) {
        section = to
    }

    /// The first two letters of a username, as the account's disc.
    private static func initials(_ name: String) -> String { String(name.prefix(2)).uppercased() }

    // MARK: - The menus

    @ViewBuilder private func menuPanel(_ which: DockMenu) -> some View {
        let close = {
            menu = nil
            docked = which == .systems ? .systems : .account
        }
        Group {
            switch which {
            case .systems:
                SystemsMenu(systems: library.systemList) { picked in
                    menu = nil
                    system = picked
                    systems = []
                    section = .systems
                }
            case .account:
                AccountMenu(close: close)
            }
        }
        .padding(.leading, (10 + 56) * dp)
        .frame(maxHeight: .infinity)
        .focusSection()
        .onExitCommand(perform: close)
    }
}

/// A dock entry's contents: the icon (or the account's disc) in a 44 dp circle, and the
/// label beside it while the dock is open.
private struct DockLabel: View {
    let symbol: String?
    let avatar: String?
    let label: String
    let current: Bool
    let open: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if let avatar {
                    Text(avatar).font(.system(size: 10 * dp, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28 * dp, height: 28 * dp).background(Sov.accent, in: Circle())
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 18 * dp, weight: .regular))
                        .foregroundStyle(current || focused ? .white : Sov.slate400)
                }
            }
            .frame(width: 44 * dp, height: 44 * dp)
            if open {
                Text(label).font(.system(size: 14 * dp, weight: .medium)).lineLimit(1)
                    .foregroundStyle(current || focused ? .white : Sov.slate400)
                    .padding(.trailing, 16 * dp)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The dock's pills: the current section filled with the accent, the focused one lit and ringed.
private struct DockButtonStyle: ButtonStyle {
    let current: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, current: current)
    }

    private struct Pill<Label: View>: View {
        let label: Label
        let current: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            label
                .background(Capsule().fill(current ? Sov.accent : focused ? .white.opacity(0.1) : .clear))
                .overlay(Capsule().stroke(.white.opacity(focused ? 0.6 : 0), lineWidth: 2 * dp))
        }
    }
}

/// The wordmark: the mark, then "Sov" in white and "Emu" in the accent.
private struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8 * dp) {
            Image("SovEmuMark").resizable().scaledToFit().frame(height: 27 * dp).foregroundStyle(Sov.accent)
            Text("Sov").foregroundStyle(.white)
            Text("Emu").foregroundStyle(Sov.accent)
        }
        .font(.system(size: 18 * dp, weight: .black))
        .allowsHitTesting(false)
    }
}

// MARK: - Menus

/// A menu pane beside the dock: the web's dropdown (panel colour, edge, heading).
private struct DockMenuPane<Content: View>: View {
    let heading: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading.uppercased())
                .font(.system(size: 12 * dp, weight: .semibold)).kerning(1 * dp).foregroundStyle(Sov.slate500)
                .padding(.horizontal, 16 * dp).padding(.top, 8 * dp).padding(.bottom, 8 * dp)
            Rectangle().fill(Sov.edge).frame(height: 1 * dp)
            ScrollView { VStack(alignment: .leading, spacing: 0) { content() }.padding(.vertical, 4 * dp) }
        }
        .frame(minWidth: 208 * dp, maxWidth: 320 * dp, maxHeight: 480 * dp, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(Sov.panel, in: RoundedRectangle(cornerRadius: 12 * dp))
        .overlay(RoundedRectangle(cornerRadius: 12 * dp).stroke(Sov.edge, lineWidth: 1 * dp))
    }
}

/// A menu row: an icon, the label (a detail under it, smaller, for a setting's trade-off), and a
/// count or status at the end.
private struct MenuRow<Leading: View>: View {
    let label: String
    var detail: String?
    var trailing: String?
    @ViewBuilder let leading: () -> Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * dp) {
                leading().frame(width: 16 * dp)
                VStack(alignment: .leading, spacing: 2 * dp) {
                    Text(label).font(.system(size: 14 * dp)).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 11 * dp)).foregroundStyle(Sov.slate500).lineLimit(2)
                    }
                }
                Spacer(minLength: 12 * dp)
                if let trailing { Text(trailing).font(.system(size: 12 * dp)).foregroundStyle(Sov.slate500) }
            }
            .padding(.horizontal, 12 * dp)
            .frame(height: detail == nil ? 40 * dp : nil)
            .frame(minHeight: detail == nil ? nil : 56 * dp)
            .frame(maxWidth: detail == nil ? .infinity : 320 * dp)
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(label: configuration.label) }

    private struct Row<Label: View>: View {
        let label: Label
        @Environment(\.isFocused) private var focused
        var body: some View {
            label
                .foregroundStyle(focused ? .white : Sov.slate300)
                .background(focused ? Color.white.opacity(0.1) : .clear)
        }
    }
}

/// The systems with games, under their makers, each with its count or a status.
private struct SystemsMenu: View {
    let systems: [SystemSummary]
    let pick: (SystemSummary) -> Void

    var body: some View {
        let groups = groupByMaker(systems.filter { $0.gameCount > 0 })
        DockMenuPane(heading: "Systems") {
            if groups.isEmpty {
                Text("No games yet.").font(.system(size: 14 * dp)).foregroundStyle(Sov.slate500)
                    .padding(.horizontal, 16 * dp).padding(.vertical, 8 * dp)
            }
            ForEach(groups, id: \.maker) { group in
                Text(group.maker.uppercased())
                    .font(.system(size: 11 * dp, weight: .semibold)).kerning(1 * dp).foregroundStyle(Sov.slate500)
                    .padding(.leading, 16 * dp).padding(.top, 8 * dp).padding(.bottom, 4 * dp)
                ForEach(group.systems) { s in
                    MenuRow(label: s.name, trailing: s.badge ?? String(s.gameCount)) {
                        Circle().fill(s.accent).frame(width: 10 * dp, height: 10 * dp)
                    } action: {
                        pick(s)
                    }
                }
            }
        }
    }
}

/// The account's menu: the app's settings, changing user or server, and signing out.
private struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    let close: () -> Void

    var body: some View {
        DockMenuPane(heading: library.user.map { "Signed in as \($0.username)" } ?? "Signed in") {
            MenuRow(label: settings.music ? "Music: on" : "Music: off") { icon("music.note") } action: {
                settings.music.toggle()
            }
            MenuRow(label: settings.screensaverMinutes == 0 ? "Screensaver: off" : "Screensaver: after \(settings.screensaverMinutes) min") {
                icon("play")
            } action: {
                let choices = AppSettings.screensaverChoices
                let at = choices.firstIndex(of: settings.screensaverMinutes) ?? 0
                settings.screensaverMinutes = choices[(at + 1) % choices.count]
            }
            MenuRow(label: settings.scanlines ? "Scan lines: on" : "Scan lines: off") { icon("line.3.horizontal") } action: {
                settings.scanlines.toggle()
            }
            MenuRow(label: "Change user or server") { icon("person.2") } action: {
                close()
                Task { await model.signOut() }
            }
            MenuRow(label: "Sign out") { icon("rectangle.portrait.and.arrow.right") } action: {
                close()
                Task { await model.signOut() }
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16 * dp)).foregroundStyle(Sov.slate300)
    }
}

extension View {
    /// Where a section's links go.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .system(let system, let open): SystemView(system: system, openFirst: open)
            }
        }
    }

    /// Back on a section's first page goes to the dock (where a second Back leaves the app), as
    /// on SovEmu.Android's TV app.
    @ViewBuilder fileprivate func backToDock(_ atRoot: Bool, _ toDock: @escaping () -> Void) -> some View {
        if atRoot { onExitCommand(perform: toDock) } else { self }
    }
}
