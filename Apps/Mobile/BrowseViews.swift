import SwiftUI
import SovEmuKit

private let surface = Color(red: 0.043, green: 0.051, blue: 0.071)
private let panel = Color(red: 0.082, green: 0.098, blue: 0.133)

/// Server address and sign-in. First-run setup happens in the web client.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    /// The server's `bootstrapConfig` for the address in the field, once it has answered.
    @State private var connected: BootstrapConfig?

    var body: some View {
        ZStack {
            surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("SovEmu").font(.system(size: 34, weight: .black))
                Text("Connect to your SovEmu server.").foregroundStyle(.secondary)
                TextField("Server address (http://192.168.1.20:8080)", text: $server)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: server) { _, address in
                        if address != model.serverURL { connected = nil }
                    }
                if let connected, let problem = connected.signInProblem {
                    // No form: this app cannot sign in here (yet).
                    Text(problem).font(.callout)
                    Button(busy ? "Connecting…" : "Try again") { Task { await connect() } }
                        .buttonStyle(.bordered).disabled(busy).frame(maxWidth: .infinity)
                } else if connected != nil {
                    TextField("Username", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Button(busy ? "Signing in…" : "Sign in") { Task { await signIn() } }
                        .buttonStyle(.borderedProminent).disabled(busy).frame(maxWidth: .infinity)
                } else {
                    Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }
                        .buttonStyle(.borderedProminent).disabled(busy).frame(maxWidth: .infinity)
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
            }
            .textFieldStyle(.roundedBorder)
            .padding(24)
            .frame(maxWidth: 420)
            .background(panel, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .onAppear {
            server = model.serverURL.isEmpty ? "http://" : model.serverURL
            connected = model.bootstrap
        }
    }

    /// Asks the address for its `bootstrapConfig`: whether a SovEmu server is there, and how to
    /// sign in to it.
    private func connect() async {
        busy = true
        defer { busy = false }
        error = nil
        model.serverURL = server
        guard let api = model.api else {
            error = "That is not a valid address."
            return
        }
        do {
            let config = try await model.refreshBootstrap()
            if config.signInProblem == nil, try await api.status().setupRequired {
                error = "Finish first-run setup in a browser at \(server) first."
                return
            }
            connected = config
        } catch {
            self.error = "No SovEmu server answered at \(server): \(error.localizedDescription)"
        }
    }

    private func signIn() async {
        guard let api = model.api else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            // A refusal carries the server's `error_description` ("Wrong username or password.").
            try await api.signIn(username: username, password: password)
            model.signedInAnew()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A horizontal carousel of systems with games, tinted by the selected one.
struct SystemsView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [Route]
    @State private var systems: [SystemSummary]?
    @State private var selected: String?
    @State private var error: String?

    private var current: SystemSummary? { systems?.first { $0.id == selected } ?? systems?.first }

    var body: some View {
        ZStack {
            RadialGradient(colors: [(current?.accent ?? .blue).opacity(0.45), surface], center: .center, startRadius: 0, endRadius: 700)
                .ignoresSafeArea()
                .animation(.easeInOut, value: selected)
            if let systems {
                if systems.isEmpty {
                    Text("No games yet: add ROMs to the server's library.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 28) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 24) {
                                ForEach(systems) { system in
                                    let focused = system.id == current?.id
                                    Button {
                                        if focused { path.append(.games(system)) } else { selected = system.id }
                                    } label: {
                                        Text(system.short)
                                            .font(.system(size: 40, weight: .black))
                                            .foregroundStyle(.white)
                                            .frame(width: focused ? 240 : 200, height: focused ? 150 : 125)
                                            .background(LinearGradient(colors: [system.accent, system.accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                        in: RoundedRectangle(cornerRadius: 24))
                                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(focused ? 0.8 : 0), lineWidth: 3))
                                            .opacity(focused ? 1 : 0.45)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 48)
                        }
                        .frame(height: 170)
                        if let current {
                            VStack(spacing: 6) {
                                Text(current.name).font(.system(size: 30, weight: .black))
                                Text("\(current.manufacturer) · \(String(current.year)) · \(current.gameCount) game\(current.gameCount == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("SovEmu")
        .toolbar {
            Button("Sign out") {
                Task { await model.signOut() }
            }
        }
        .task {
            do {
                systems = try await model.api?.systems().filter { $0.gameCount > 0 } ?? []
                await model.nameDevice()
            } catch let e as APIError where e.isUnauthenticated {
                model.signedIn = false
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A system's games, with the selected game's details.
struct GamesView: View {
    @Environment(AppModel.self) private var model
    let system: SystemSummary
    @Binding var path: [Route]
    @State private var games: [Game]?

    var body: some View {
        ZStack {
            RadialGradient(colors: [system.accent.opacity(0.35), surface], center: .topLeading, startRadius: 0, endRadius: 900)
                .ignoresSafeArea()
            if let games {
                List(games) { game in
                    Button {
                        path.append(.play(system, game))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title).font(.headline)
                                if !game.tags.isEmpty { Text(game.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text("Played \(game.playCount)×").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "play.fill").foregroundStyle(system.accent)
                        }
                    }
                    .listRowBackground(panel.opacity(0.8))
                }
                .scrollContentBackground(.hidden)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(system.name)
        .task { games = (try? await model.api?.games(system: system.id)) ?? [] }
    }
}
