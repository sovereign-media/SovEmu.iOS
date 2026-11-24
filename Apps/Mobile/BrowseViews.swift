import SwiftUI
import SovEmuKit

private let surface = Sov.surface
private let panel = Sov.panel

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
