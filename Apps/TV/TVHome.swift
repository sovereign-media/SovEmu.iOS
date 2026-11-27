// Home on a TV, as SovEmu.Android's TV app (`Home.kt`): a hero of featured games over their
// artwork, moving on by itself, then rows of games to continue, favourites, systems, recently
// added and top rated games and each collection. A "Continue playing" card opens a panel here;
// any other game card opens the game's panel on its system's page; the hero's Play starts at
// once. Sizes are Android's in dp, times `dp`.
import SwiftUI
import SovEmuKit

struct TVHomeView: View {
    @Environment(Library.self) private var library
    @Binding var path: [Route]

    var body: some View {
        Group {
            switch library.home {
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                Text(message).foregroundStyle(Sov.red300).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let feed): TVHomeContent(feed: feed, path: $path)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct TVHomeContent: View {
    @Environment(Library.self) private var library
    @Environment(\.playGame) private var play
    let feed: HomeFeed
    @Binding var path: [Route]
    /// The "Continue playing" game whose panel is open.
    @State private var resumeId: Int64?
    /// The panel Game details closed, to open again on coming back to Home.
    @State private var reopen: Int64?
    @FocusState private var focus: String?

    var body: some View {
        let systems = library.systemList.filter { $0.gameCount > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TVHero(games: feed.featured, empty: systems.isEmpty, focus: $focus)
                VStack(alignment: .leading, spacing: 40 * dp) {
                    if !feed.recent.isEmpty {
                        TVHomeRow(title: "Continue playing", symbol: "clock.arrow.circlepath") {
                            ForEach(feed.recent) { g in
                                TVGameCard(game: g, wide: true, focus: $focus, key: "recent:\(g.id)") { resumeId = g.id }
                            }
                        }
                    }
                    games("Favourites", "heart", "favourite", feed.favourites)
                    if !systems.isEmpty {
                        TVHomeRow(title: "Systems", symbol: "gamecontroller") {
                            ForEach(systems) { s in TVSystemCard(system: s, focus: $focus) }
                        }
                    }
                    games("Recently added", "sparkles", "added", feed.added)
                    games("Top rated", "star", "rated", feed.topRated)
                    ForEach(feed.collections.filter { !$0.games.isEmpty }) { c in
                        games(c.name, "folder", "collection:\(c.id)", c.games)
                    }
                }
                .offset(y: -32 * dp)
            }
            .padding(.bottom, 112 * dp)
        }
        .scrollClipDisabled()
        .ignoresSafeArea()
        .task {
            // The hero's Play has the focus at first (the top card where there is no hero), as
            // on SovEmu.Android's TV app; the dock opens only when it is gone to.
            if focus == nil { focus = feed.featured.isEmpty ? feed.recent.first.map { "recent:\($0.id)" } : "hero" }
        }
        .onAppear {
            guard let id = reopen else { return }
            reopen = nil
            resumeId = id
        }
        .tvContinuePanel(
            game: resumeGame, system: resumeGame.flatMap { library.system($0.system) },
            onPlay: { start in
                if let game = resumeGame, let system = library.system(game.system) { play(system, game, start) }
            },
            onDetails: {
                guard let game = resumeGame, let system = library.system(game.system) else { return }
                reopen = game.id
                resumeId = nil
                path.append(.system(system, open: game.id))
            },
            onClose: closeResume)
    }

    private var resumeGame: Game? { feed.recent.first { $0.id == resumeId } }

    /// A row of game cards that open the game's panel on its system's page.
    @ViewBuilder private func games(_ title: String, _ symbol: String, _ key: String, _ games: [Game]) -> some View {
        if !games.isEmpty {
            TVHomeRow(title: title, symbol: symbol) {
                ForEach(games) { g in TVGameCard(game: g, wide: false, focus: $focus, key: "\(key):\(g.id)") }
            }
        }
    }

    /// Closes the Continue panel; the focus goes back to its card.
    private func closeResume() {
        guard let id = resumeId else { return }
        resumeId = nil
        DispatchQueue.main.async { focus = "recent:\(id)" }
    }
}

// MARK: - The hero

/// Featured games one at a time over their artwork, moving on by itself every 9 s.
private struct TVHero: View {
    @Environment(Library.self) private var library
    @Environment(\.playGame) private var play
    let games: [Game]
    let empty: Bool
    var focus: FocusState<String?>.Binding
    @State private var index = 0

    var body: some View {
        let box = Rectangle().fill(.clear).aspectRatio(16 / 6.3, contentMode: .fit).frame(maxWidth: .infinity)
        if games.isEmpty {
            box.overlay {
                RadialGradient(colors: [Color(hex: 0x1E2A4A), Sov.surface], center: .center, startRadius: 0, endRadius: 700)
                VStack(spacing: 12 * dp) {
                    Image(systemName: "gamecontroller").font(.system(size: 40 * dp)).foregroundStyle(Sov.slate500)
                    Text(empty
                         ? "No games yet. Add ROMs to the library (one folder per system: nes/, snes/, …) and rescan."
                         : "No artwork yet: fetch game information on the Library page to fill this space.")
                        .font(.system(size: 16 * dp)).foregroundStyle(Sov.slate400).multilineTextAlignment(.center)
                }
                .padding(32 * dp)
            }
        } else {
            let game = games[min(index, games.count - 1)]
            let system = library.system(game.system)
            box.overlay {
                ZStack(alignment: .bottomLeading) {
                    TVSlide(game: game, system: system).id(game.id).transition(.opacity)
                    LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.5), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.7), .init(color: .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack { Spacer(); LinearGradient(colors: [.clear, Sov.surface], startPoint: .top, endPoint: .bottom).frame(height: 96 * dp) }
                    VStack(alignment: .leading, spacing: 0) {
                        TVBadge(short: system?.short ?? game.system.uppercased(), colour: system?.accent ?? Sov.accent)
                        Text(game.title)
                            .font(.system(size: 44 * dp, weight: .black)).foregroundStyle(.white).lineLimit(2)
                            .padding(.top, 12 * dp)
                        if !game.byline.isEmpty {
                            Text(game.byline).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate300).padding(.top, 8 * dp)
                        }
                        if let description = game.description {
                            Text(description).font(.system(size: 14 * dp)).lineSpacing(7 * dp).foregroundStyle(Sov.slate300)
                                .lineLimit(3).padding(.top, 12 * dp)
                        }
                        Button {
                            if let system { play(system, game, .ask) }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(TVButtonStyle(variant: .light))
                        .focused(focus, equals: "hero")
                        .padding(.top, 20 * dp)
                    }
                    .frame(maxWidth: 672 * dp, alignment: .leading)
                    .padding(.horizontal, 48 * dp)
                    .padding(.bottom, 64 * dp)
                    if games.count > 1 {
                        HStack(spacing: 6 * dp) {
                            ForEach(games.indices, id: \.self) { i in
                                Capsule().fill(.white.opacity(i == index ? 1 : 0.4))
                                    .frame(width: (i == index ? 20 : 8) * dp, height: 8 * dp)
                            }
                        }
                        .padding(24 * dp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .animation(.easeInOut(duration: 0.7), value: index)
            }
            .clipped()
            .task(id: index) {
                guard games.count > 1 else { return }
                try? await Task.sleep(for: .seconds(9))
                guard !Task.isCancelled else { return }
                index = (index + 1) % games.count
            }
        }
    }
}

/// One featured game's backdrop: its screenshot, else its box art blurred behind a sharp copy.
private struct TVSlide: View {
    let game: Game
    let system: SystemSummary?

    var body: some View {
        ZStack(alignment: .trailing) {
            tile(system?.accent ?? Sov.accent, mix: 0.25)
            if let image = game.image {
                RemoteImage(path: image)
            } else if let thumb = game.thumb {
                RemoteImage(path: thumb).blur(radius: 24).opacity(0.5).scaleEffect(1.1)
                RemoteImage(path: game.cover ?? thumb, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * dp))
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.7 }
                    .padding(.trailing, 64 * dp)
            }
        }
    }
}

// MARK: - Rows and cards

/// A titled, horizontally scrolling row.
private struct TVHomeRow<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * dp) {
            HStack(spacing: 8 * dp) {
                Image(systemName: symbol).font(.system(size: 18 * dp)).foregroundStyle(Sov.slate400)
                Text(title).font(.system(size: 18 * dp, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 32 * dp)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16 * dp) { content() }
                    .padding(.horizontal, 32 * dp).padding(.vertical, 12 * dp)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

/// A game: box art (portrait), or where the player left off (landscape, `wide`).
struct TVGameCard: View {
    @Environment(Library.self) private var library
    let game: Game
    let wide: Bool
    var focus: FocusState<String?>.Binding
    let key: String
    /// What opening it does instead of the game's panel on its system's page.
    var onOpen: (() -> Void)?
    @State private var covered = false

    var body: some View {
        let system = library.system(game.system)
        let short = system?.short ?? game.system.uppercased()
        VStack(alignment: .leading, spacing: 8 * dp) {
            Group {
                if let onOpen {
                    Button(action: onOpen) { picture(system, short) }
                } else {
                    NavigationLink(value: system.map { Route.system($0, open: game.id) }) { picture(system, short) }
                }
            }
            .buttonStyle(TVFocusCardStyle())
            .focused(focus, equals: key)
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title).font(.system(size: 14 * dp, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                let ago = wide ? game.lastPlayedAt.map { " · " + formatAgo(GameIndex.playedAt($0), now: Int64(Date().timeIntervalSince1970)) } ?? "" : ""
                releaseLine(game.release, short + ago, first: false).font(.system(size: 12 * dp)).foregroundStyle(Sov.slate400).lineLimit(1)
            }
            .padding(.horizontal, 2 * dp)
        }
        .frame(width: (wide ? 288 : 160) * dp)
    }

    private func picture(_ system: SystemSummary?, _ short: String) -> some View {
        ZStack {
            // Only the Continue row shows where the player left off; the others show box art.
            if wide, let shot = game.autoSave?.screenshotUrl {
                Color.black
                RemoteImage(path: shot, contentMode: .fit, pixelated: true)
            } else {
                if !covered {
                    tile(system?.accent ?? Sov.accent)
                    Text(short).font(.system(size: 28 * dp, weight: .black)).foregroundStyle(.white.opacity(0.8))
                }
                RemoteImage(path: game.imageSmall ?? game.thumb, contentMode: wide ? .fill : .fit) { loaded in
                    if wide { covered = loaded }
                }
            }
        }
        .aspectRatio(wide ? 16 / 9 : 3 / 4, contentMode: .fit)
    }
}

/// A system: its tile (the short name, and the server's photo of the hardware where it has one).
private struct TVSystemCard: View {
    let system: SystemSummary
    var focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * dp) {
            NavigationLink(value: Route.system(system, open: nil)) {
                ZStack {
                    tile(system.accent, mix: 0.35)
                    let short = Text(system.short).font(.system(size: 36 * dp, weight: .black)).foregroundStyle(.white)
                    if let photo = system.photoUrl {
                        // The server's photo of the hardware on the right, the short name on the
                        // left, as on the web and Android TV.
                        short.padding(.leading, 12 * dp).frame(maxWidth: .infinity, alignment: .leading)
                        GeometryReader { box in
                            RemoteImage(path: photo, contentMode: .fit)
                                .frame(width: box.size.width * 0.58, height: box.size.height * 0.76)
                                .padding(8 * dp)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    } else {
                        short
                    }
                    if let badge = system.badge {
                        Text(badge).font(.system(size: 11 * dp, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8 * dp).padding(.vertical, 2 * dp)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4 * dp))
                            .padding(.horizontal, 12 * dp).padding(.vertical, 8 * dp)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(height: 128 * dp)
                .overlay(RoundedRectangle(cornerRadius: 16 * dp).stroke(.white.opacity(0.1), lineWidth: 1 * dp))
            }
            .buttonStyle(TVFocusCardStyle(radius: 16 * dp))
            .focused(focus, equals: "system:\(system.id)")
            VStack(alignment: .leading, spacing: 0) {
                Text(system.name).font(.system(size: 14 * dp, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                Text("\(system.manufacturer) · \(system.year) · \(system.gameCount) game\(system.gameCount == 1 ? "" : "s")")
                    .font(.system(size: 12 * dp)).foregroundStyle(Sov.slate400).lineLimit(1)
            }
            .padding(.horizontal, 2 * dp)
        }
        .frame(width: 224 * dp)
    }
}

// MARK: - Styles

/// SovEmu.Android's `FocusCard`: the focused card grows by 5% with a white ring (4 dp, 80%).
struct TVFocusCardStyle: ButtonStyle {
    var radius: CGFloat = 12 * dp

    func makeBody(configuration: Configuration) -> some View {
        Card(label: configuration.label, radius: radius)
    }

    private struct Card<Label: View>: View {
        let label: Label
        let radius: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            label
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(focused ? 0.8 : 0), lineWidth: 4 * dp))
                .scaleEffect(focused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// SovEmu.Android's `SovButton`: 44 dp tall (36 small), 6 dp corners, a 3 dp white ring outside
/// it when focused, its label 16 sp semibold.
struct TVButtonStyle: ButtonStyle {
    enum Variant { case primary, light, outline, ghost }
    var variant = Variant.primary
    var large = true

    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, variant: variant, large: large)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let variant: Variant
        let large: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let (bg, fg): (Color, Color) = switch variant {
            case .primary: (Sov.accent, .white)
            case .light: (.white, Sov.slate950)
            case .outline: (.clear, Sov.slate200)
            case .ghost: (focused ? .white.opacity(0.1) : .clear, Sov.slate400)
            }
            label
                .labelStyle(TVButtonLabelStyle())
                .font(.system(size: (large ? 16 : 14) * dp, weight: .semibold))
                .foregroundStyle(fg)
                .lineLimit(1)
                .padding(.horizontal, (large ? 20 : 12) * dp)
                .frame(height: (large ? 44 : 36) * dp)
                .background(bg, in: RoundedRectangle(cornerRadius: 6 * dp))
                .overlay { if variant == .outline { RoundedRectangle(cornerRadius: 6 * dp).stroke(Sov.edge, lineWidth: 1 * dp) } }
                .padding(3 * dp)
                .overlay(RoundedRectangle(cornerRadius: 9 * dp).stroke(.white.opacity(focused ? 0.7 : 0), lineWidth: 3 * dp))
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

private struct TVButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8 * dp) {
            configuration.icon.font(.system(size: 14 * dp))
            configuration.title
        }
    }
}

/// The system's coloured badge ("SNES").
struct TVBadge: View {
    let short: String
    let colour: Color

    var body: some View {
        Text(short).font(.system(size: 12 * dp, weight: .black)).foregroundStyle(.white)
            .padding(.horizontal, 8 * dp).padding(.vertical, 2 * dp)
            .background(colour, in: RoundedRectangle(cornerRadius: 6 * dp))
    }
}
