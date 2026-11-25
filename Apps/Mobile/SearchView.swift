import SovEmuKit
import SwiftUI

/// Search across every system, as the other clients' search page: the matching games as covers,
/// asked for once typing pauses; one opens its system with its panel open. The query stays with
/// the screen, so coming back from that system shows the same results.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: Load<[Game]>?

    /// How many results the server sends (`Query.search`'s default).
    private static let limit = 48

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let line = summary {
                    Text(line).font(.system(size: 14)).foregroundStyle(isFailure ? Sov.red300 : Sov.slate400)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                    ForEach(results?.value ?? []) { GameCard(game: $0, wide: false) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Sov.surface)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titles, makers, genres")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task(id: query) {
            // Asks after a pause in typing; a new query cancels the one before it.
            let q = String(query.trimmingCharacters(in: .whitespaces).prefix(100))
            guard !q.isEmpty else {
                results = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let api = model.api else { return }
            do {
                results = .ready(try await api.search(q))
            } catch is CancellationError {
            } catch {
                results = .failed(error.localizedDescription)
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = results { return true }
        return false
    }

    private var summary: String? {
        switch results {
        case nil, .loading: nil
        case .failed(let message): message
        case .ready(let games):
            switch games.count {
            case 0: "No games match. Try fewer words."
            case 1: "1 game"
            case Self.limit: "The first \(Self.limit) games"
            default: "\(games.count) games"
            }
        }
    }
}

/// A game's collections: each of this user's collections as a toggle that puts the game in it or
/// takes it out, and a field to make a new one with the game in it. Home follows every change.
struct CollectionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var choices: [CollectionChoice]?
    @State private var error: String?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(game.title).foregroundStyle(Sov.slate300) }
                Section("Collections") {
                    if let choices {
                        if choices.isEmpty {
                            Text("No collections yet: name one below to start it with this game.").foregroundStyle(Sov.slate500)
                        }
                        ForEach(choices) { c in
                            Toggle(c.name, isOn: Binding(get: { c.member }, set: { toggle(c, $0) }))
                        }
                    } else if error == nil {
                        ProgressView()
                    }
                }
                Section("New collection") {
                    TextField("Name", text: $name).onSubmit(create).submitLabel(.done)
                    Button("Create", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error { Section { Text(error).foregroundStyle(Sov.red300) } }
            }
            .scrollContentBackground(.hidden)
            .background(Sov.surface)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: game.id) {
            do {
                choices = try await model.api?.collectionChoices(gameId: game.id)
            } catch {
                self.error = "Could not load the collections: \(error.localizedDescription)"
            }
        }
    }

    private func toggle(_ c: CollectionChoice, _ member: Bool) {
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

/// The systems with games, under their makers, each with its count or a status, as the other
/// clients' Systems menu.
struct SystemsList: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            switch library.systems {
            case .loading: ProgressView()
            case .failed(let message): Text(message).foregroundStyle(Sov.red300).padding()
            case .ready(let all):
                let groups = groupByMaker(all.filter { $0.gameCount > 0 })
                if groups.isEmpty {
                    Text("No games yet: add ROMs to the server's library.").foregroundStyle(Sov.slate500)
                } else {
                    List {
                        ForEach(groups, id: \.maker) { group in
                            Section(group.maker) {
                                ForEach(group.systems) { s in
                                    NavigationLink(value: Route.system(s, open: nil)) {
                                        HStack(spacing: 12) {
                                            Circle().fill(s.accent).frame(width: 10, height: 10)
                                            Text(s.name)
                                            Spacer()
                                            Text(s.badge ?? "\(s.gameCount)").font(.system(size: 13)).foregroundStyle(Sov.slate500)
                                        }
                                    }
                                    .listRowBackground(Sov.panel)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Sov.surface)
        .navigationTitle("Systems")
        .refreshable { library.refresh() }
    }
}

/// The account and the app's settings, as the other clients' account menu.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("Signed in as", value: library.user?.username ?? "…")
                LabeledContent("Server", value: model.serverURL)
            }
            Section {
                Toggle(isOn: $settings.music) { Label("Music", systemImage: "music.note") }
                Picker(selection: $settings.screensaverMinutes) {
                    ForEach(AppSettings.screensaverChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "After \(minutes) min").tag(minutes)
                    }
                } label: {
                    Label("Screensaver", systemImage: "play.rectangle")
                }
                Toggle(isOn: $settings.scanlines) { Label("Scan lines", systemImage: "line.3.horizontal") }
            } footer: {
                Text("The screensaver plays games' videos after a while without a touch or a button press, and keeps the screen awake in the menus until then. Music follows the silent switch.")
            }
            Section {
                // A TV signs itself in with a code; this approves one from here.
                NavigationLink {
                    SignInTVView()
                } label: {
                    Label(TvSignIn.title, systemImage: "tv")
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Sov.surface)
        .navigationTitle(library.user?.username ?? "Account")
    }
}
