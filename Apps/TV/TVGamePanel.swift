// The Apple TV's game panel and collections drawer, as SovEmu.Android's `GamePanel`
// (`:common:feature` SystemParts.kt) and `CollectionsDrawer` (Collections.kt) on its TV app. The
// iPhone and iPad draw theirs in Apps/Shared (SystemView.swift's `GamePanel`, SearchView.swift's
// `CollectionsSheet`).
import SovEmuKit
import SwiftUI


/// A game's details in a panel on the right edge, over the grid: artwork (and its video snap),
/// facts, Continue / Start over or Play, the favourite, collections and patch, the description,
/// saves to start from and play history. It takes the focus when it opens (Continue, else Play)
/// and keeps it until Menu closes it.
struct TVGamePanel: View {
    let game: Game
    let system: SystemSummary
    let slots: [SaveSlot]
    let patches: [GamePatch]
    let notice: String?
    /// Counts the collections drawer's closings: each sends the focus back to Collections.
    var backToCollections = 0
    let onPlay: (Start) -> Void
    let onFavourite: () -> Void
    let onCollections: () -> Void
    let onPatch: (GamePatch?) -> Void
    let onClose: () -> Void

    private enum Focus: Hashable { case first, collections }
    @FocusState private var focus: Focus?

    var body: some View {
        // The auto save comes with the game, so Continue never waits on the saves request.
        let auto = game.autoSave != nil || slots.contains { $0.slot == autoSlot }
        VStack(spacing: 0) {
            TVPanelArt(game: game, system: system)
                .overlay(alignment: .topTrailing) { TVPanelClose() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16 * dp) {
                    facts
                    HStack(spacing: 8 * dp) {
                        if auto {
                            TVSovButton("Continue", symbol: "play.fill") { onPlay(.continue) }
                                .focused($focus, equals: .first)
                            TVSovButton("Start over", symbol: "arrow.counterclockwise", variant: .outline) { onPlay(.new) }
                        } else {
                            TVSovButton("Play", symbol: "play.fill") { onPlay(.new) }
                                .focused($focus, equals: .first)
                        }
                    }
                    HStack(spacing: 8 * dp) {
                        TVSovButton(game.favourite ? "Favourite" : "Add to favourites",
                                    symbol: game.favourite ? "heart.fill" : "heart", variant: .outline, large: false,
                                    iconTint: game.favourite ? Sov.red300 : nil, action: onFavourite)
                        TVSovButton("Collections", symbol: "text.badge.plus", variant: .outline, large: false,
                                    action: onCollections)
                            .focused($focus, equals: .collections)
                    }
                    // Select, again and again, steps through the original and each patch: one
                    // button, no menu to navigate on a remote.
                    if !patches.isEmpty {
                        TVSovButton("Patch: \(game.patch ?? "Original")", symbol: "doc.badge.gearshape",
                                    variant: .outline, large: false) { onPatch(nextPatch(patches, after: game.patch)) }
                    }
                    if let notice { Text(notice).font(.system(size: 14 * dp)).foregroundStyle(Sov.red300) }
                    if let description = game.description {
                        Text(description).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate300).lineSpacing(6 * dp)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !slots.isEmpty {
                        VStack(alignment: .leading, spacing: 8 * dp) {
                            TVEyebrow("Start from a save")
                            FlowLayout(spacing: 10 * dp, lineSpacing: 10 * dp) {
                                ForEach(slots.sorted { $0.slot < $1.slot }, id: \.slot) { save in
                                    TVSaveThumb(save: save) { onPlay(.fromSlot(save.slot)) }
                                }
                            }
                        }
                    }
                    history
                }
                .padding(.horizontal, 24 * dp)
                .padding(.top, 8 * dp)
                .padding(.bottom, 24 * dp)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tvSidePanelChrome(onClose: onClose)
        .onAppear { DispatchQueue.main.async { focus = .first } }
        .onChange(of: game.id) { DispatchQueue.main.async { focus = .first } }
        .onChange(of: backToCollections) { DispatchQueue.main.async { focus = .collections } }
    }

    /// The title, its release and tags, the facts under them and the ESRB badge beside.
    private var facts: some View {
        HStack(alignment: .top, spacing: 16 * dp) {
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title).font(.system(size: 24 * dp, weight: .black)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let release = game.release {
                    Text(release).font(.system(size: 14 * dp, weight: .medium)).foregroundStyle(Sov.amber200).padding(.top, 4 * dp)
                }
                if !game.tags.isEmpty {
                    Text(game.tags.joined(separator: " · ")).font(.system(size: 12 * dp)).foregroundStyle(Sov.slate500)
                        .padding(.top, 4 * dp)
                }
                FlowLayout(spacing: 16 * dp, lineSpacing: 4 * dp) {
                    if let year = game.year { TVFact(symbol: "calendar", text: year) }
                    if let maker = game.developer ?? game.publisher { TVFact(symbol: "building.2", text: maker) }
                    if let genre = game.genre { TVFact(symbol: "tag", text: genre) }
                    if let most = maxPlayers(game.players) {
                        TVFact(symbol: "person.2", text: most == 1 ? "1 player" : "\(game.players ?? "") players")
                    }
                    if game.discs > 1 { TVFact(symbol: partSymbol(game.partKind), text: "\(game.discs) discs") }
                    if let stars = formatRating(game.rating) { TVFact(symbol: "star", text: stars) }
                    if !game.modes.isEmpty { TVFact(symbol: "gamecontroller", text: game.modes.joined(separator: ", ")) }
                    if !game.series.isEmpty { TVFact(symbol: "books.vertical", text: game.series.joined(separator: ", ")) }
                    if !game.themes.isEmpty { TVFact(symbol: "sparkles", text: game.themes.joined(separator: ", ")) }
                }
                .padding(.top, 12 * dp)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let esrb = game.esrb, let url = game.esrbBadgeUrl { EsrbBadge(rating: esrb, url: url, height: 56 * dp) }
        }
    }

    private var history: some View {
        let now = Int64(Date().timeIntervalSince1970)
        let played = game.playCount > 0
            ? "Played \(game.playCount)× · last \(formatAgo(GameIndex.playedAt(game.lastPlayedAt), now: now))" : "Not played yet"
        return VStack(alignment: .leading, spacing: 12 * dp) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1 * dp)
            Text("\(played) · \(game.path) · \(formatSize(game.size))").font(.system(size: 12 * dp)).foregroundStyle(Sov.slate500)
        }
        .padding(.top, 4 * dp)
    }
}

/// The panel's picture: the system's tile and badge under the game's artwork, its video snap over
/// them after a moment, and the box cover inset bottom left when the artwork is a screen.
private struct TVPanelArt: View {
    let game: Game
    let system: SystemSummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(tile(system.accent))
            Text(system.short).font(.system(size: 60 * dp, weight: .black)).foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            RemoteImage(path: game.image ?? game.cover ?? game.thumb, contentMode: game.image != nil ? .fill : .fit)
            // Muted: the menus' music plays on.
            if game.video != nil { VideoSnap(path: game.video) }
            VStack(spacing: 0) {
                Color.clear
                LinearGradient(colors: [.clear, Sov.surface.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            }
            if game.image != nil, let cover = game.cover ?? game.thumb {
                GeometryReader { proxy in
                    RemoteImage(path: cover, contentMode: .fit)
                        .frame(width: proxy.size.height * 0.5 * 3 / 4, height: proxy.size.height * 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 6 * dp))
                        .padding(.leading, 20 * dp).padding(.bottom, 12 * dp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }
}

/// A save, as a button that starts the game from it: its screenshot, slot and age. Focused, the
/// screenshot gets a white edge and a play mark.
private struct TVSaveThumb: View {
    let save: SaveSlot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) { EmptyView() }
            .buttonStyle(TVSaveStyle(save: save))
    }
}

private struct TVSaveStyle: ButtonStyle {
    let save: SaveSlot

    func makeBody(configuration: Configuration) -> some View { TVSaveBody(save: save) }
}

private struct TVSaveBody: View {
    let save: SaveSlot
    @Environment(\.isFocused) private var focused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6 * dp)
        VStack(alignment: .leading, spacing: 4 * dp) {
            ZStack {
                Color.black
                RemoteImage(path: save.screenshotUrl, contentMode: .fit, pixelated: true)
                if focused {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill").font(.system(size: 20 * dp)).foregroundStyle(.white)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.8 : 0.1), lineWidth: (focused ? 3 : 1) * dp))
            Text(save.slot == autoSlot ? "Auto save" : "Slot \(save.slot)").font(.system(size: 12 * dp, weight: .semibold))
                .foregroundStyle(focused ? .white : Sov.slate300)
            Text(formatAgo(Int64(save.savedAt), now: Int64(Date().timeIntervalSince1970))).font(.system(size: 11 * dp))
                .foregroundStyle(Sov.slate500)
        }
        .frame(width: 112 * dp)
    }
}

// MARK: - Collections

/// A game's collections, in a drawer from the right (as the filters): each of this user's
/// collections as a toggle that puts the game in it or takes it out, and a field to make a new
/// one with the game in it. Home follows every change. Menu closes it.
struct TVCollectionsDrawer: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    let game: Game
    let onClose: () -> Void
    @State private var choices: [CollectionChoice]?
    @State private var error: String?
    @State private var name = ""

    private enum Focus: Hashable { case first, field }
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TVDrawerHeader(symbol: "folder.badge.person.crop", title: "Collections")
            ScrollView {
                VStack(alignment: .leading, spacing: 20 * dp) {
                    Text(game.title).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate300)
                    if let choices {
                        if choices.isEmpty {
                            Text("No collections yet: name one below to start it with this game.")
                                .font(.system(size: 14 * dp)).foregroundStyle(Sov.slate500)
                        } else {
                            VStack(alignment: .leading, spacing: 8 * dp) {
                                ForEach(Array(choices.enumerated()), id: \.element.id) { i, c in
                                    if i == 0 {
                                        TVToggleRow(title: c.name, on: c.member) { toggle(c) }.focused($focus, equals: .first)
                                    } else {
                                        TVToggleRow(title: c.name, on: c.member) { toggle(c) }
                                    }
                                }
                            }
                        }
                    } else if error == nil {
                        Text("Loading…").font(.system(size: 14 * dp)).foregroundStyle(Sov.slate500)
                    }
                    VStack(alignment: .leading, spacing: 8 * dp) {
                        TVEyebrow("New collection")
                        TVTextBox(label: "Name", text: $name, onSubmit: create)
                            .focused($focus, equals: .field)
                            .onChange(of: name) { _, now in if now.count > 64 { name = String(now.prefix(64)) } }
                        TVSovButton("Create", symbol: "folder.badge.plus", variant: .outline, large: false, action: create)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error { Text(error).font(.system(size: 14 * dp)).foregroundStyle(Sov.red300) }
                }
                .padding(20 * dp)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tvDrawerChrome(onClose: onClose)
        .task(id: game.id) {
            do {
                choices = try await model.api?.collectionChoices(gameId: game.id)
            } catch {
                self.error = "Could not load the collections: \(error.localizedDescription)"
            }
            // Once loaded: the first collection, or the field when there are none yet.
            focus = (choices ?? []).isEmpty ? .field : .first
        }
    }

    private func toggle(_ c: CollectionChoice) {
        let member = !c.member
        choices = choices?.map { $0.id == c.id ? CollectionChoice(id: $0.id, name: $0.name, member: member) : $0 }
        Task {
            do {
                try await model.api?.setInCollection(collectionId: c.id, gameId: game.id, member: member)
                error = nil
                library.collectionsChanged()
            } catch {
                choices = choices?.map { $0.id == c.id ? CollectionChoice(id: $0.id, name: $0.name, member: !member) : $0 }
                self.error = "Could not change \(c.name): \(error.localizedDescription)"
            }
        }
    }

    private func create() {
        // The field is cleared at once, so the value is taken first.
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, let api = model.api else { return }
        name = ""
        Task {
            do {
                let id = try await api.createCollection(name: wanted)
                try await api.setInCollection(collectionId: id, gameId: game.id, member: true)
                error = nil
                choices = ((choices ?? []) + [CollectionChoice(id: id, name: wanted, member: true)])
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                library.collectionsChanged()
            } catch {
                name = wanted
                self.error = "Could not create the collection: \(error.localizedDescription)"
            }
        }
    }
}
