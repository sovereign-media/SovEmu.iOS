// A system's games on the Apple TV, as SovEmu.Android's TV system page (`:common:feature-tv`
// System.kt, with the cover card, filter drawer and jump strip of `:common:feature`
// SystemParts.kt). The iPhone and iPad draw theirs in Apps/Shared/SystemView.swift; both read the
// same `Library` and `GameIndex`.
import SovEmuKit
import SwiftUI


/// Where the focus is on the system page, so it can be put back where it was after an overlay.
enum TVSystemFocus: Hashable {
    case game(Int64)
    case sort, filters, jump
}

/// One system's games: a header with a capsule of chips (Sort, Filters, Jump), a grid of covers,
/// and a side panel with the chosen game's details. With the panel open the remote stays in it;
/// Menu closes it onto its game's card. Play/Pause opens the filters (Start does on Android).
///
/// Opened on a game from another screen (`openFirst`: Home, Search), the grid scrolls to it and
/// its panel opens; closing the panel lands on its card, as from any other game.
struct TVSystemView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.playGame) private var play
    let system: SystemSummary
    let openFirst: Int64?

    @State private var query = ""
    @State private var filters = GameFilters()
    @State private var filtersOpen = false
    @State private var sortOpen = false
    @State private var collectionsOpen = false
    /// Counts the collections drawer's closings: each sends the focus back to the panel's button.
    @State private var backToCollections = 0
    @State private var openId: Int64?
    @State private var started = false
    @State private var jump: Int?
    @State private var notice: String?
    @State private var slots: [SaveSlot] = []
    @State private var patches: [GamePatch] = []
    @State private var scrollTarget: Int64?
    /// The game card last focused, for the focus to go back to after an overlay.
    @State private var lastGame: Int64?
    @FocusState private var focus: TVSystemFocus?

    var body: some View {
        let load = library.games(system.id)
        ZStack(alignment: .topLeading) {
            // The page's tint: the system's colour from the top-left corner, as on Android. It is
            // the page's own full-screen fill (Android's NavFrame draws no surface or background
            // picture under this page: `paintsBackground`), and it reaches under the dock.
            RadialGradient(colors: [Sov.surface.mix(with: system.accent, by: 0.25), Sov.surface], center: .topLeading,
                           startRadius: 0, endRadius: 1800)
                .padding(.leading, -64 * dp)
                .ignoresSafeArea()
            switch load {
            case .loading:
                header(shown: nil, total: nil, jump: nil, blocked: true)
                    .padding(.horizontal, 32 * dp).padding(.top, 40 * dp)
                    .ignoresSafeArea()
            case .failed(let message):
                Text(message).font(.system(size: 14 * dp)).foregroundStyle(Sov.red300)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let index):
                games(index)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { library.want(system.id) }
        .onAppear {
            guard !started else { return }
            started = true
            openId = openFirst
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
        .onChange(of: load.value?.games.first(where: { $0.id == openId })?.patch) {
            // A patched game's saves are its own: they change with the patch.
            guard let id = openId, let api = model.api else { return }
            Task { slots = (try? await api.saves(gameId: id)) ?? [] }
        }
        .onChange(of: focus) { _, now in
            if case .game(let id) = now { lastGame = id }
        }
    }

    // MARK: - The grid

    private func games(_ index: GameIndex) -> some View {
        let shown = index.query(query, filters: filters, sort: settings.sort)
        let stops = jumpStops(shown)
        let open = openId.flatMap { id in index.games.first { $0.id == id } }
        let blocked = open != nil || filtersOpen || sortOpen || jump != nil
        let canJump = shown.count > 12 && stops.count > 1
        return ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24 * dp) {
                        header(shown: shown.count, total: index.games.count,
                               jump: canJump ? { openJump(shown, stops) } : nil, blocked: blocked)
                            .padding(.top, 40 * dp).padding(.bottom, 8 * dp)
                            .zIndex(1)
                        if shown.isEmpty { empty(index) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 152 * dp), spacing: 16 * dp, alignment: .top)],
                                  alignment: .leading, spacing: 24 * dp) {
                            ForEach(shown) { game in
                                TVCoverCard(game: game, system: system, isOpen: game.id == openId) { openId = game.id }
                                    .focused($focus, equals: .game(game.id))
                                    .id(game.id)
                            }
                        }
                        .disabled(blocked)
                        .focusSection()
                    }
                    .padding(.horizontal, 32 * dp)
                    .padding(.bottom, 112 * dp)
                }
                .scrollClipDisabled()
                .ignoresSafeArea()
                .defaultFocus($focus, shown.first.map { .game($0.id) })
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    proxy.scrollTo(target, anchor: .top)
                    scrollTarget = nil
                }
                .onAppear {
                    // Opened on a game (from Home or Search): scroll to it.
                    if let openFirst { DispatchQueue.main.async { proxy.scrollTo(openFirst, anchor: .center) } }
                }
            }
            .onPlayPauseCommand { if !blocked { filtersOpen = true } }

            if let open { panel(open) }
            if filtersOpen {
                scrim(0.6)
                TVFilterDrawer(index: index, query: $query, filters: $filters) {
                    filtersOpen = false
                    refocus(.filters)
                }
                .transition(.move(edge: .trailing))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .ignoresSafeArea()
            }
            if let at = jump, stops.indices.contains(at) {
                TVJumpStrip(stops: stops, index: at,
                            onIndex: { i in follow(i, shown, stops) },
                            onCommit: { commitJump(shown, stops[at]) },
                            onCancel: {
                                jump = nil
                                refocus(.jump)
                            })
            }
        }
        .animation(.easeOut(duration: 0.25), value: openId != nil)
        .animation(.easeOut(duration: 0.25), value: filtersOpen)
    }

    private func empty(_ index: GameIndex) -> some View {
        Text(index.games.isEmpty ? "No games for this system yet." : "No games match. Try fewer words, or clear the filters.")
            .font(.system(size: 16 * dp)).foregroundStyle(Sov.slate400)
            .padding(.vertical, 80 * dp).padding(.horizontal, 32 * dp)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12 * dp))
            .overlay(RoundedRectangle(cornerRadius: 12 * dp).strokeBorder(.white.opacity(0.15), lineWidth: 1 * dp))
            .padding(.vertical, 48 * dp)
    }

    private func scrim(_ alpha: Double) -> some View {
        Color.black.opacity(alpha).ignoresSafeArea().transition(.opacity)
    }

    // MARK: - The header

    /// The system, its count and the chips beside it.
    private func header(shown: Int?, total: Int?, jump: (() -> Void)?, blocked: Bool) -> some View {
        let filterCount = filters.count + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
        return HStack(alignment: .center, spacing: 16 * dp) {
            HStack(spacing: 12 * dp) {
                TVSystemBadge(short: system.short, colour: system.accent, large: true)
                Text(system.name).font(.system(size: 30 * dp, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                if let total, let shown {
                    Text(shown == total ? "\(total) games" : "\(shown) of \(total)")
                        .font(.system(size: 14 * dp)).foregroundStyle(Sov.slate400).fixedSize()
                }
                if system.biosMissing {
                    HStack(spacing: 6 * dp) {
                        Image(systemName: "cpu").font(.system(size: 13 * dp))
                        Text("BIOS missing: games will not start").font(.system(size: 12 * dp, weight: .semibold))
                    }
                    .foregroundStyle(Sov.amber200)
                    .padding(.horizontal, 12 * dp).padding(.vertical, 4 * dp)
                    .background(Color(hex: 0xF59E0B).opacity(0.2), in: Capsule())
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if total != nil {
                TVChipStrip {
                    TVChip(title: settings.sort.label, symbol: "arrow.up.arrow.down") { sortOpen = true }
                        .focused($focus, equals: .sort)
                        .disabled(blocked)
                        .dropdownBelow(gap: 12 * dp) { if sortOpen { sortMenu } }
                    TVChipDivider()
                    TVChip(title: filterCount > 0 ? "Filters (\(filterCount))" : "Filters", symbol: "slider.horizontal.3",
                           on: filterCount > 0) { filtersOpen = true }
                        .focused($focus, equals: .filters)
                        .disabled(blocked)
                    // Kept in place outside title order, dimmed: letters only mean something in
                    // title order.
                    if let jump {
                        TVChip(title: "Jump", symbol: "character.book.closed", action: jump)
                            .focused($focus, equals: .jump)
                            .disabled(blocked || settings.sort != .title)
                    }
                }
                .focusSection()
            }
        }
        .frame(minHeight: 42 * dp)
        // Across the whole width: up from any card reaches the chips, wherever they are.
        .focusSection()
    }

    private var sortMenu: some View {
        TVDropdown(options: GameSort.allCases.map { TVOption(value: $0, label: $0.label) },
                   isOn: { $0 == settings.sort },
                   onPick: { s in
                       settings.sort = s
                       sortOpen = false
                       refocus(.sort)
                   },
                   onClose: {
                       sortOpen = false
                       refocus(.sort)
                   })
    }

    // MARK: - The panel

    private func panel(_ game: Game) -> some View {
        ZStack(alignment: .trailing) {
            scrim(0.6)
            TVGamePanel(
                game: game, system: system, slots: slots, patches: patches, notice: notice,
                backToCollections: backToCollections,
                onPlay: { start in play(system, game, start) },
                onFavourite: {
                    Task { notice = await library.setFavourite(game, !game.favourite).map { "Could not change favourites: \($0)" } }
                },
                onCollections: { collectionsOpen = true },
                onPatch: { patch in
                    Task { notice = await library.setPatch(game, patch).map { "Could not change the patch: \($0)" } }
                },
                onClose: closePanel)
                .disabled(collectionsOpen)
                .transition(.move(edge: .trailing))
            if collectionsOpen {
                scrim(0.6)
                TVCollectionsDrawer(game: game) {
                    collectionsOpen = false
                    backToCollections += 1
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: collectionsOpen)
    }

    private func closePanel() {
        guard let id = openId else { return }
        openId = nil
        refocus(.game(id))
    }

    /// An overlay closed: the focus goes back to what opened it, once the page can take it again.
    private func refocus(_ target: TVSystemFocus) {
        DispatchQueue.main.async { focus = target }
    }

    // MARK: - Jump

    private func openJump(_ shown: [Game], _ stops: [String]) {
        let current = lastGame.flatMap { id in shown.first { $0.id == id } }.map { letterOf($0.title) }
        jump = max(0, stops.firstIndex(of: current ?? "") ?? 0)
    }

    /// The strip rests on a letter a moment before the grid follows it.
    private func follow(_ i: Int, _ shown: [Game], _ stops: [String]) {
        jump = i
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard jump == i else { return }
            let at = jumpTo(shown, stops[i])
            if shown.indices.contains(at) { scrollTarget = shown[at].id }
        }
    }

    private func commitJump(_ shown: [Game], _ letter: String) {
        jump = nil
        let at = jumpTo(shown, letter)
        guard shown.indices.contains(at) else { return }
        scrollTarget = shown[at].id
        let id = shown[at].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .game(id) }
    }
}

// MARK: - The cover card

/// A cover in the grid: box art (else the system's tile and the title), a pill for a multi-part
/// game and a tick for one played before, with its title and a year and players line under it.
/// Focused, the cover grows 5% with a white ring, as Android's `FocusCard`; the open game's has an
/// accent edge.
struct TVCoverCard: View {
    let game: Game
    let system: SystemSummary
    let isOpen: Bool
    let onOpen: () -> Void
    @State private var loaded = false
    @State private var imageAspect: Double?

    private var cardAspect: Double { system.boxAspect > 0 ? system.boxAspect : defaultBoxAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * dp) {
            Button(action: onOpen) {
                ZStack {
                    if !loaded {
                        Rectangle().fill(tile(system.accent))
                        Text(game.title).font(.system(size: 14 * dp, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            .lineLimit(4).multilineTextAlignment(.center).padding(12 * dp)
                    }
                    // Art of another shape than the system's boxes is shown whole, not cut.
                    RemoteImage(
                        path: game.thumb ?? game.imageSmall,
                        contentMode: artFills(imageAspect ?? 0, cardAspect) ? .fill : .fit,
                        shape: $imageAspect
                    ) { loaded = $0 }
                }
                .overlay(alignment: .topLeading) {
                    if game.discs > 1 {
                        HStack(spacing: 4 * dp) {
                            Image(systemName: partSymbol(game.partKind)).font(.system(size: 12 * dp))
                            Text("\(game.discs)").font(.system(size: 12 * dp, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8 * dp).frame(height: 24 * dp)
                        .background(.black.opacity(0.7), in: Capsule()).padding(8 * dp)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.playCount > 0 {
                        Image(systemName: "checkmark.circle").font(.system(size: 15 * dp)).foregroundStyle(.white)
                            .frame(width: 24 * dp, height: 24 * dp).background(.black.opacity(0.7), in: Circle()).padding(8 * dp)
                    }
                }
                // The card takes the shape of the system's boxes (SNES landscape, NES portrait).
                .aspectRatio(cardAspect, contentMode: .fit)
            }
            .buttonStyle(TVCoverStyle(isOpen: isOpen))
            .accessibilityLabel(game.title)
            VStack(alignment: .leading, spacing: 2 * dp) {
                Text(game.title).font(.system(size: 14 * dp, weight: .semibold)).foregroundStyle(Sov.slate100).lineLimit(1)
                let players = maxPlayers(game.players)
                let line = (game.year ?? game.tags.first ?? system.short) + (players.map { $0 >= 2 ? " · \($0) players" : "" } ?? "")
                releaseLine(game.release, line, first: true).font(.system(size: 12 * dp)).foregroundStyle(Sov.slate400).lineLimit(1)
            }
            .padding(.horizontal, 2 * dp)
        }
    }
}

private struct TVCoverStyle: ButtonStyle {
    let isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        TVCoverBody(label: configuration.label, isOpen: isOpen, pressed: configuration.isPressed)
    }
}

private struct TVCoverBody<Label: View>: View {
    let label: Label
    let isOpen: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12 * dp)
        label
            .clipShape(shape)
            .overlay {
                if focused {
                    shape.strokeBorder(.white.opacity(0.8), lineWidth: 4 * dp)
                } else if isOpen {
                    shape.strokeBorder(Sov.accent, lineWidth: 2 * dp)
                }
            }
            .scaleEffect(pressed ? 1.02 : focused ? 1.05 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - The jump strip

/// Jump to a letter, as Android's `JumpStrip`: a carousel of letter discs, the current one large in
/// the middle. Left and right move along it (the grid follows after a moment), select goes to the
/// letter's first game, Menu goes back.
private struct TVJumpStrip: View {
    let stops: [String]
    let index: Int
    let onIndex: (Int) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Sov.surface.opacity(0.5).ignoresSafeArea()
            Button(action: onCommit) {
                HStack(spacing: 12 * dp) {
                    chevron("chevron.left", shown: index > 0)
                    HStack(spacing: 4 * dp) {
                        ForEach(max(0, index - 3)..<index, id: \.self) { disc(stops[$0]) }
                    }
                    .frame(width: 152 * dp, alignment: .trailing)
                    Text(stops[index]).font(.system(size: 30 * dp, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 64 * dp, height: 64 * dp)
                        .background(Sov.accent.opacity(0.2), in: Circle())
                        .overlay(Circle().strokeBorder(Sov.accent, lineWidth: 2 * dp))
                    HStack(spacing: 4 * dp) {
                        ForEach((index + 1)..<min(stops.count, index + 4), id: \.self) { disc(stops[$0]) }
                    }
                    .frame(width: 152 * dp, alignment: .leading)
                    chevron("chevron.right", shown: index < stops.count - 1)
                }
                .padding(.horizontal, 16 * dp).padding(.vertical, 12 * dp)
                .background(Sov.surface.opacity(0.95), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1 * dp))
            }
            .buttonStyle(TVPlainStyle())
            .focused($focused)
            .onMoveCommand { direction in
                switch direction {
                case .left: onIndex(max(0, index - 1))
                case .right: onIndex(min(stops.count - 1, index + 1))
                default: break
                }
            }
            .onExitCommand(perform: onCancel)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func disc(_ stop: String) -> some View {
        Text(stop).font(.system(size: 18 * dp, weight: .bold)).foregroundStyle(.white).frame(width: 44 * dp, height: 44 * dp)
    }

    private func chevron(_ symbol: String, shown: Bool) -> some View {
        ZStack { if shown { Image(systemName: symbol).font(.system(size: 16 * dp, weight: .semibold)).foregroundStyle(Sov.slate400) } }
            .frame(width: 32 * dp, height: 32 * dp)
    }
}

/// A button that draws only its label: what it is shows the focus itself.
struct TVPlainStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
