import SovEmuKit
import SwiftUI

/// One system's games, as the other clients' system page: a header with its chips (Sort,
/// Filters, Jump), a grid of covers, and a panel with the chosen game's details (a column beside
/// the grid on an iPad, a sheet on an iPhone).
///
/// Opened on a game from another screen (`openFirst`: Home, Search), closing that game's panel
/// goes back there rather than to this grid: the panel was what was asked for.
struct SystemView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.playGame) private var play
    let system: SystemSummary
    let openFirst: Int64?

    @State private var query = ""
    @State private var filters = GameFilters()
    @State private var filtersOpen = false
    @State private var jumpOpen = false
    @State private var collectionsOpen = false
    @State private var openId: Int64?
    @State private var notice: String?
    @State private var slots: [SaveSlot] = []
    @State private var patches: [GamePatch] = []
    @State private var scrollTarget: Int64?

    var body: some View {
        let load = library.games(system.id)
        ZStack {
            RadialGradient(colors: [Sov.surface.mix(with: system.accent, by: 0.25), Sov.surface], center: .topLeading,
                           startRadius: 0, endRadius: 1400)
                .ignoresSafeArea()
            switch load {
            case .loading:
                VStack { header(shown: nil, total: nil, index: nil); Spacer(); ProgressView(); Spacer() }
                    .padding(.horizontal, padding)
            case .failed(let message):
                Text(message).foregroundStyle(Sov.red300).padding()
            case .ready(let index):
                grid(index)
            }
        }
        .navigationTitle(system.name)
        .inlineTitle()
        .task { library.want(system.id) }
        .onAppear { if openId == nil, let openFirst { openId = openFirst } }
        .sidePanel(isPresented: Binding(get: { openId != nil }, set: { if !$0 { closePanel() } })) {
            if let index = load.value, let game = index.games.first(where: { $0.id == openId }) {
                GamePanel(
                    game: game, system: system, slots: slots, patches: patches, notice: notice,
                    onPlay: { start in play(system, game, start) },
                    onFavourite: {
                        Task { notice = await library.setFavourite(game, !game.favourite).map { "Could not change favourites: \($0)" } }
                    },
                    onCollections: { collectionsOpen = true },
                    onPatch: { patch in
                        Task { notice = await library.setPatch(game, patch).map { "Could not change the patch: \($0)" } }
                    },
                    onClose: closePanel)
                    .sheet(isPresented: $collectionsOpen) {
                        CollectionsSheet(game: game).presentationDetents([.medium, .large])
                    }
            } else {
                ProgressView()
            }
        }
        .task(id: openId) {
            // The panel's patches, and its saves after a pause (moving quickly through games does
            // not ask for each).
            patches = []
            slots = []
            notice = nil
            guard let id = openId, let api = model.api else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            async let p = try? api.patches(gameId: id)
            async let s = try? api.saves(gameId: id)
            patches = await p ?? []
            slots = await s ?? []
        }
        .onChange(of: library.games(system.id).value?.games.first(where: { $0.id == openId })?.patch) {
            // A patched game's saves are its own: they change with the patch.
            guard let id = openId, let api = model.api else { return }
            Task { slots = (try? await api.saves(gameId: id)) ?? [] }
        }
    }

    private var padding: CGFloat { size == .regular ? 32 : 16 }

    private func grid(_ index: GameIndex) -> some View {
        let shown = index.query(query, filters: filters, sort: settings.sort)
        let stops = jumpStops(shown)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(shown: shown.count, total: index.games.count, index: index,
                           jump: settings.sort == .title && shown.count > 12 && stops.count > 1)
                    if shown.isEmpty {
                        Text(index.games.isEmpty ? "No games for this system yet." : "No games match. Try fewer words, or clear the filters.")
                            .foregroundStyle(Sov.slate400)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80).padding(.horizontal, 32)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
                            .padding(.vertical, 48)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: size == .regular ? 152 : 140), spacing: 16)], spacing: 24) {
                        ForEach(shown) { game in
                            CoverCard(game: game, system: system, isOpen: game.id == openId) { openId = game.id }
                                .id(game.id)
                        }
                    }
                }
                .padding(.horizontal, padding)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
            .onAppear {
                // Opened on a game (from Home or Search): scroll to it.
                if let openFirst { DispatchQueue.main.async { proxy.scrollTo(openFirst, anchor: .center) } }
            }
            .sheet(isPresented: $filtersOpen) {
                FilterSheet(index: index, query: $query, filters: $filters).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $jumpOpen) {
                JumpSheet(stops: stops) { letter in
                    jumpOpen = false
                    let at = jumpTo(shown, letter)
                    if shown.indices.contains(at) { scrollTarget = shown[at].id }
                }
                .presentationDetents([.height(300)])
            }
        }
    }

    /// The system, its count and the chips beside it.
    private func header(shown: Int?, total: Int?, index: GameIndex?, jump: Bool = false) -> some View {
        let title = HStack(spacing: 12) {
            SystemBadge(short: system.short, colour: system.accent, large: true)
            Text(system.name).font(.system(size: 30, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            if let total, let shown {
                Text(shown == total ? "\(total) games" : "\(shown) of \(total)").font(.system(size: 14)).foregroundStyle(Sov.slate400)
            }
        }
        let filterCount = filters.count + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(minLength: 16); if total != nil { chips(filterCount: filterCount, jump: jump) } }
                VStack(alignment: .leading, spacing: 16) { title; if total != nil { chips(filterCount: filterCount, jump: jump) } }
            }
            if system.biosMissing {
                Label("BIOS missing: games will not start", systemImage: "cpu")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Sov.amber200)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color(hex: 0xF59E0B).opacity(0.2), in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private func chips(filterCount: Int, jump: Bool) -> some View {
        @Bindable var settings = settings
        return HStack(spacing: 2) {
            Menu {
                Picker("Sort", selection: $settings.sort) {
                    ForEach(GameSort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                ChipLabel(title: settings.sort.label, symbol: "arrow.up.arrow.down")
            }
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 20).padding(.horizontal, 4)
            Button { filtersOpen = true } label: {
                ChipLabel(title: filterCount > 0 ? "Filters (\(filterCount))" : "Filters", symbol: "slider.horizontal.3", on: filterCount > 0)
            }
            if jump {
                Button { jumpOpen = true } label: { ChipLabel(title: "Jump", symbol: "textformat.abc") }
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(Sov.surface.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func closePanel() {
        // Still the game this screen was opened on: back to where it was opened from.
        if let openFirst, openId == openFirst {
            openId = nil
            dismiss()
            return
        }
        openId = nil
    }
}

/// A cover in the grid: box art (else the system's tile and the title), with a pill for a
/// multi-part game and a tick for one played before.
private struct CoverCard: View {
    let game: Game
    let system: SystemSummary
    let isOpen: Bool
    let onOpen: () -> Void
    @State private var loaded = false
    @State private var imageAspect: Double?

    private var cardAspect: Double { system.boxAspect > 0 ? system.boxAspect : defaultBoxAspect }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if !loaded {
                        tile(system.accent)
                        Text(game.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            .lineLimit(4).multilineTextAlignment(.center).padding(12)
                    }
                    // Art of another shape than the system's boxes is shown whole, not cut.
                    RemoteImage(
                        path: game.thumb ?? game.imageSmall,
                        contentMode: artFills(imageAspect ?? 0, cardAspect) ? .fill : .fit,
                        shape: $imageAspect
                    ) { loaded = $0 }
                }
                // The card takes the shape of the system's boxes (SNES landscape, NES portrait).
                .aspectRatio(cardAspect, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if game.discs > 1 {
                        Label("\(game.discs)", systemImage: partSymbol(game.partKind))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(.black.opacity(0.7), in: Capsule()).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.playCount > 0 {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(.black.opacity(0.7), in: Circle()).padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { if isOpen { RoundedRectangle(cornerRadius: 12).stroke(Sov.accent, lineWidth: 2) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                    let players = maxPlayers(game.players)
                    let line = (game.year ?? game.tags.first ?? system.short) + (players.map { $0 >= 2 ? " · \($0) players" : "" } ?? "")
                    releaseLine(game.release, line, first: true).font(.system(size: 12)).foregroundStyle(Sov.slate400).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A game's details: artwork (and its video snap), facts, Continue / Start over or Play, the
/// favourite, collections and patch, the description, saves to start from and play history.
struct GamePanel: View {
    let game: Game
    let system: SystemSummary
    let slots: [SaveSlot]
    let patches: [GamePatch]
    let notice: String?
    let onPlay: (Start) -> Void
    let onFavourite: () -> Void
    let onCollections: () -> Void
    let onPatch: (GamePatch?) -> Void
    let onClose: () -> Void

    var body: some View {
        // The auto save comes with the game, so Continue never waits on the saves request.
        let auto = game.autoSave != nil || slots.contains { $0.slot == autoSlot }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                art
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(game.title).font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                            Spacer(minLength: 0)
                            if let esrb = game.esrb, let url = game.esrbBadgeUrl { EsrbBadge(rating: esrb, url: url, height: 56) }
                        }
                        if let release = game.release {
                            Text(release).font(.system(size: 14, weight: .medium)).foregroundStyle(Sov.amber200)
                        }
                        if !game.tags.isEmpty {
                            Text(game.tags.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Sov.slate500)
                        }
                        FlowLayout(spacing: 16, lineSpacing: 4) {
                            if let year = game.year { Fact(symbol: "calendar", text: year) }
                            if let maker = game.developer ?? game.publisher { Fact(symbol: "building.2", text: maker) }
                            if let genre = game.genre { Fact(symbol: "tag", text: genre) }
                            if let most = maxPlayers(game.players) {
                                Fact(symbol: "person.2", text: most == 1 ? "1 player" : "\(game.players ?? "") players")
                            }
                            if game.discs > 1 { Fact(symbol: partSymbol(game.partKind), text: "\(game.discs) discs") }
                            if let stars = formatRating(game.rating) { Fact(symbol: "star", text: stars) }
                            if !game.modes.isEmpty { Fact(symbol: "gamecontroller", text: game.modes.joined(separator: ", ")) }
                            if !game.series.isEmpty { Fact(symbol: "books.vertical", text: game.series.joined(separator: ", ")) }
                            if !game.themes.isEmpty { Fact(symbol: "theatermasks", text: game.themes.joined(separator: ", ")) }
                        }
                        .padding(.top, 8)
                    }
                    HStack(spacing: 8) {
                        if auto {
                            Button { onPlay(.continue) } label: { Label("Continue", systemImage: "play.fill") }.buttonStyle(.sov())
                            Button { onPlay(.new) } label: { Label("Start over", systemImage: "arrow.counterclockwise") }
                                .buttonStyle(.sov(.outline))
                        } else {
                            Button { onPlay(.new) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.sov())
                        }
                    }
                    HStack(spacing: 8) {
                        Button(action: onFavourite) {
                            Label(game.favourite ? "Favourite" : "Add to favourites", systemImage: game.favourite ? "heart.fill" : "heart")
                                .foregroundStyle(game.favourite ? Sov.red300 : Sov.slate200)
                        }
                        .buttonStyle(.sov(.outline, large: false))
                        Button(action: onCollections) { Label("Collections", systemImage: "text.badge.plus") }
                            .buttonStyle(.sov(.outline, large: false))
                    }
                    // One button steps through the original and each patch.
                    if !patches.isEmpty {
                        Button { onPatch(nextPatch(patches, after: game.patch)) } label: {
                            Label("Patch: \(game.patch ?? "Original")", systemImage: "doc.badge.gearshape")
                        }
                        .buttonStyle(.sov(.outline, large: false))
                    }
                    if let notice { Text(notice).font(.system(size: 14)).foregroundStyle(Sov.red300) }
                    if let description = game.description {
                        Text(description).font(.system(size: 14)).foregroundStyle(Sov.slate300).lineSpacing(6)
                    }
                    if !slots.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow("Start from a save")
                            FlowLayout(spacing: 10, lineSpacing: 10) {
                                ForEach(slots.sorted { $0.slot < $1.slot }, id: \.slot) { save in
                                    SaveThumb(save: save) { onPlay(.fromSlot(save.slot)) }
                                }
                            }
                        }
                    }
                    let now = Int64(Date().timeIntervalSince1970)
                    let history = game.playCount > 0
                        ? "Played \(game.playCount)× · last \(formatAgo(GameIndex.playedAt(game.lastPlayedAt), now: now))" : "Not played yet"
                    VStack(alignment: .leading, spacing: 12) {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                        Text("\(history) · \(game.path) · \(formatSize(game.size))").font(.system(size: 12)).foregroundStyle(Sov.slate500)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Sov.surface)
    }

    private var art: some View {
        ZStack(alignment: .bottomLeading) {
            tile(system.accent)
            Text(system.short).font(.system(size: 60, weight: .black)).foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            RemoteImage(path: game.image ?? game.cover ?? game.thumb, contentMode: game.image != nil ? .fill : .fit)
            // Its video snap, after a moment, over the artwork (muted: the menus' music plays on).
            if game.video != nil { VideoSnap(path: game.video) }
            LinearGradient(colors: [.clear, Sov.surface.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            if game.image != nil && (game.cover ?? game.thumb) != nil {
                RemoteImage(path: game.cover ?? game.thumb, contentMode: .fit)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 20).padding(.bottom, 12)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.5), in: Circle())
            }
            .padding(12)
        }
    }
}

/// A save, as a button that starts the game from it: its screenshot, slot and age.
private struct SaveThumb: View {
    let save: SaveSlot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Color.black
                    RemoteImage(path: save.screenshotUrl, contentMode: .fit, pixelated: true)
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                Text(save.slot == autoSlot ? "Auto save" : "Slot \(save.slot)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Sov.slate300)
                Text(formatAgo(Int64(save.savedAt), now: Int64(Date().timeIntervalSince1970))).font(.system(size: 11)).foregroundStyle(Sov.slate500)
            }
            .frame(width: 112)
        }
        .buttonStyle(.plain)
    }
}

/// Search and filters: search, favourites, played or not, players and genres.
private struct FilterSheet: View {
    let index: GameIndex
    @Binding var query: String
    @Binding var filters: GameFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let genres = Array(index.genreCounts.prefix(24))
        let on = filters.count + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Search titles, makers, genres", text: $query)
                        .roundedField().autocorrectionDisabled().textInputAutocapitalization(.never)
                    section("Lists") {
                        TogglePill(on: filters.favourites, action: { filters.favourites.toggle() }) {
                            Image(systemName: "heart").foregroundStyle(filters.favourites ? .white : Sov.red300)
                            Text("Favourites")
                        }
                    }
                    section("Played") {
                        TogglePill(on: filters.played == .played, action: { filters.played = filters.played == .played ? nil : .played }) {
                            Text("Played before")
                        }
                        TogglePill(on: filters.played == .unplayed, action: { filters.played = filters.played == .unplayed ? nil : .unplayed }) {
                            Text("Not played yet")
                        }
                    }
                    if index.knowsPlayers {
                        section("Players") {
                            TogglePill(on: filters.multiplayer, action: { filters.multiplayer.toggle() }) { Text("2 players or more") }
                        }
                    }
                    if !genres.isEmpty {
                        section("Genre") {
                            ForEach(genres, id: \.genre) { entry in
                                let isOn = filters.genres.contains(entry.genre)
                                TogglePill(on: isOn, action: {
                                    if isOn { filters.genres.remove(entry.genre) } else { filters.genres.insert(entry.genre) }
                                }) {
                                    Text(entry.genre)
                                    Text("\(entry.count)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                    if !index.knowsPlayers && genres.isEmpty {
                        Text("Player and genre filters appear once game information has been fetched for these games.")
                            .font(.system(size: 14)).foregroundStyle(Sov.slate500)
                    }
                    if on > 0 {
                        Button {
                            filters = GameFilters()
                            query = ""
                        } label: {
                            Label("Clear search and filters", systemImage: "xmark").font(.system(size: 14)).foregroundStyle(Sov.slate400)
                        }
                    }
                }
                .padding(20)
            }
            .background(Sov.surface)
            .navigationTitle(on > 0 ? "Filters · \(on) on" : "Filters")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            FlowLayout(spacing: 8, lineSpacing: 8) { content() }
        }
    }
}

/// Jump to a letter: the letters some shown game files under.
private struct JumpSheet: View {
    let stops: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Jump to")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                ForEach(stops, id: \.self) { stop in
                    Button { onPick(stop) } label: {
                        Text(stop).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Sov.accent.opacity(0.2), in: Circle())
                            .overlay(Circle().stroke(Sov.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sov.surface)
    }
}

/// Lays its children out left to right, wrapping to a new line as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
