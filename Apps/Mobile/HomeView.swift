import SovEmuKit
import SwiftUI

/// Home, as the other clients': a hero of featured games over rows of games to continue,
/// favourites, systems, recently added games and each collection. A game card opens its panel
/// on its system's page (Continue or Start over from there); the hero's Play starts at once.
struct HomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            switch library.home {
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                Text(message).foregroundStyle(Sov.red300).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let feed): HomeContent(feed: feed)
            }
        }
        .background(Sov.surface)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { library.refresh() }
    }
}

private struct HomeContent: View {
    @Environment(Library.self) private var library
    let feed: HomeFeed

    var body: some View {
        let systems = library.systemList.filter { $0.gameCount > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Hero(games: feed.featured, empty: systems.isEmpty)
                if !feed.recent.isEmpty {
                    HomeRow(title: "Continue playing", symbol: "clock.arrow.circlepath") {
                        ForEach(feed.recent) { GameCard(game: $0, wide: true) }
                    }
                }
                if !feed.favourites.isEmpty {
                    HomeRow(title: "Favourites", symbol: "heart") { ForEach(feed.favourites) { GameCard(game: $0, wide: false) } }
                }
                if !systems.isEmpty {
                    HomeRow(title: "Systems", symbol: "gamecontroller") { ForEach(systems) { SystemCard(system: $0) } }
                }
                if !feed.added.isEmpty {
                    HomeRow(title: "Recently added", symbol: "sparkles") { ForEach(feed.added) { GameCard(game: $0, wide: false) } }
                }
                ForEach(feed.collections.filter { !$0.games.isEmpty }) { c in
                    HomeRow(title: c.name, symbol: "folder") { ForEach(c.games) { GameCard(game: $0, wide: false) } }
                }
            }
            .padding(.bottom, 48)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The hero: featured games one at a time over their artwork, moving on by itself every 9 s.
private struct Hero: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.playGame) private var play
    let games: [Game]
    let empty: Bool
    @State private var index = 0

    var body: some View {
        let wide = size == .regular
        if games.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "gamecontroller").font(.system(size: 44)).foregroundStyle(Sov.slate500)
                Text(empty
                     ? "No games yet. Add ROMs to the library (one folder per system: nes/, snes/, …) and rescan."
                     : "No artwork yet: fetch game information on the Library page to fill this space.")
                    .foregroundStyle(Sov.slate400).multilineTextAlignment(.center)
            }
            .padding(32)
            // Clear of the status bar and an iPad's floating tab bar, which the hero runs under.
            .padding(.top, wide ? 72 : 48)
            .frame(maxWidth: .infinity)
            .aspectRatio(wide ? 16 / 6.3 : 1, contentMode: .fit)
            .background(RadialGradient(colors: [Color(hex: 0x1E2A4A), Sov.surface], center: .center, startRadius: 0, endRadius: 500))
        } else {
            TabView(selection: $index) {
                ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                    Slide(game: game, system: library.system(game.system), wide: wide) {
                        if let system = library.system(game.system) { play(system, game, .ask) }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: games.count > 1 ? .always : .never))
            .frame(maxWidth: .infinity)
            .aspectRatio(wide ? 16 / 6.3 : 0.9, contentMode: .fit)
            .task(id: index) {
                guard games.count > 1 else { return }
                try? await Task.sleep(for: .seconds(9))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.7)) { index = (index + 1) % games.count }
            }
        }
    }
}

/// One featured game: its screenshot (else its box art, blurred, behind a sharp copy), its title,
/// what is known of it, and Play.
private struct Slide: View {
    let game: Game
    let system: SystemSummary?
    let wide: Bool
    let onPlay: () -> Void

    var body: some View {
        let short = system?.short ?? game.system.uppercased()
        ZStack(alignment: .bottomLeading) {
            ZStack {
                tile(system?.accent ?? Sov.accent, mix: 0.25)
                if game.image != nil {
                    RemoteImage(path: game.image)
                } else if game.thumb != nil {
                    RemoteImage(path: game.thumb).blur(radius: 24).opacity(0.5).scaleEffect(1.1)
                    if wide {
                        HStack {
                            Spacer()
                            RemoteImage(path: game.thumb, contentMode: .fit)
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 40)
                                .padding(.trailing, 64)
                        }
                    }
                }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.5),
                                   .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.7),
                                   .init(color: Sov.surface, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                SystemBadge(short: short, colour: system?.accent ?? Sov.accent)
                Text(game.title)
                    .font(.system(size: wide ? 44 : 30, weight: .black))
                    .foregroundStyle(.white).lineLimit(2).padding(.top, 12)
                if !game.byline.isEmpty {
                    Text(game.byline).font(.system(size: 14)).foregroundStyle(Sov.slate300).padding(.top, 8)
                }
                if let description = game.description {
                    Text(description).font(.system(size: 14)).foregroundStyle(Sov.slate300)
                        .lineLimit(wide ? 3 : 2).padding(.top, 12)
                }
                HStack(spacing: 8) {
                    Button(action: onPlay) { Label("Play", systemImage: "play.fill") }.buttonStyle(.sov(.light))
                    if let system {
                        NavigationLink(value: Route.system(system, open: nil)) {
                            Label("More \(short) games", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(.sov(.glass))
                    }
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: 672, alignment: .leading)
            .padding(.leading, wide ? 48 : 24).padding(.trailing, 48).padding(.bottom, wide ? 64 : 48)
        }
        .clipped()
    }
}

/// A titled, horizontally scrolling row.
private struct HomeRow<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: title, symbol: symbol).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) { content() }
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
    }
}

/// A game: box art (portrait), or where the player left off (landscape, `wide`). It opens the
/// game's panel on its system's page.
struct GameCard: View {
    @Environment(Library.self) private var library
    let game: Game
    let wide: Bool
    @State private var covered = false

    var body: some View {
        let system = library.system(game.system)
        let short = system?.short ?? game.system.uppercased()
        NavigationLink(value: system.map { Route.system($0, open: game.id) }) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    // Only the Continue row shows where the player left off; the others show box art.
                    if wide, let shot = game.autoSave?.screenshotUrl {
                        Color.black
                        RemoteImage(path: shot, contentMode: .fit, pixelated: true)
                    } else {
                        if !covered {
                            tile(system?.accent ?? Sov.accent)
                            Text(short).font(.system(size: 28, weight: .black)).foregroundStyle(.white.opacity(0.8))
                        }
                        RemoteImage(path: game.image ?? game.thumb, contentMode: wide ? .fill : .fit) { loaded in
                            if wide { covered = loaded }
                        }
                    }
                }
                .aspectRatio(wide ? 16 / 9 : 3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                    let ago = wide ? game.lastPlayedAt.map { " · " + formatAgo(GameIndex.playedAt($0), now: Int64(Date().timeIntervalSince1970)) } ?? "" : ""
                    releaseLine(game.release, short + ago, first: false).font(.system(size: 12)).foregroundStyle(Sov.slate400).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: wide ? 288 : 160)
        }
        .buttonStyle(.plain)
    }
}

private struct SystemCard: View {
    let system: SystemSummary

    var body: some View {
        NavigationLink(value: Route.system(system, open: nil)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    tile(system.accent, mix: 0.35)
                    Text(system.short).font(.system(size: 36, weight: .black)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let badge = system.badge {
                        Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
                .frame(width: 224, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(system.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                    Text("\(system.manufacturer) · \(String(system.year)) · \(system.gameCount) game\(system.gameCount == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Sov.slate400).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 224)
        }
        .buttonStyle(.plain)
    }
}
