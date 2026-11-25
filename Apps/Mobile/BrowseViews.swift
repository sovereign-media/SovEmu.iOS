import AuthenticationServices
import SwiftUI
import SovEmuKit

private let surface = Sov.surface
private let panel = Sov.panel

/// Server address and sign-in. As Sovereign's phones: *Sign in* opens the server's own sign-in
/// page in the system browser (the code flow with PKCE, as the mobile client); a code to approve
/// elsewhere and the password are the other ways in. First-run setup happens in the web client.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    /// The password form, asked for instead of the browser.
    @State private var passwordAsked = false
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    /// The server's `bootstrapConfig` for the address in the field, once it has answered.
    @State private var connected: BootstrapConfig?
    /// Signing in with a code, asked for (a server with no password sign-in offers only that).
    @State private var pairingAsked = false

    var body: some View {
        ZStack {
            surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("SovEmu").font(.system(size: 34, weight: .black))
                Text("Connect to your SovEmu server.").foregroundStyle(.secondary)
                TextField("Server address (http://192.168.1.20:8080)", text: $server)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: server) { _, address in
                        if address != model.serverURL {
                            connected = nil
                            pairingAsked = false
                            passwordAsked = false
                        }
                    }
                if let connected, let problem = connected.signInProblem {
                    // No form: this app cannot sign in here (yet).
                    Text(problem).font(.callout)
                    Button(busy ? "Connecting…" : "Try again") { Task { await connect() } }
                        .buttonStyle(.bordered).disabled(busy).frame(maxWidth: .infinity)
                } else if let connected, let api = model.api,
                          connected.canPair && (pairingAsked || !(connected.canUsePassword || connected.canUseBrowser)) {
                    PairingView(
                        api: api,
                        onSignedIn: { model.signedInAnew() },
                        onUsePassword: connected.canUsePassword || connected.canUseBrowser ? { pairingAsked = false } : nil,
                        backLabel: connected.canUseBrowser ? "Sign in another way" : PairingText.usePassword)
                } else if let connected, connected.canUseBrowser && !passwordAsked {
                    Button { Task { await signInWithBrowser() } } label: {
                        Text(busy ? "Signing in…" : "Sign in").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(busy)
                    if connected.canPair {
                        Button { pairingAsked = true; error = nil } label: {
                            Label("Sign in with a code", systemImage: "iphone").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).disabled(busy)
                    }
                    if connected.canUsePassword {
                        Button(PairingText.usePassword) { passwordAsked = true; error = nil }
                            .frame(maxWidth: .infinity).disabled(busy)
                    }
                } else if let connected {
                    TextField("Username", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Button(busy ? "Signing in…" : "Sign in") { Task { await signIn() } }
                        .buttonStyle(.borderedProminent).disabled(busy).frame(maxWidth: .infinity)
                    // The other ways in: a code to approve elsewhere, and the browser.
                    if connected.canPair {
                        Button { pairingAsked = true; error = nil } label: {
                            Label("Sign in with a code", systemImage: "iphone").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).disabled(busy)
                    }
                    if connected.canUseBrowser {
                        Button("Sign in with your browser") { passwordAsked = false; error = nil }
                            .frame(maxWidth: .infinity).disabled(busy)
                    }
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

    /// The server's own sign-in page in the system browser, then the code exchanged. The browser
    /// session shares Safari's sign-ins (not ephemeral), as Sovereign's phones'; a cancel is silent.
    private func signInWithBrowser() async {
        guard let api = model.api, let request = await api.browserSignIn() else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: request.authorizeURL, callbackURLScheme: request.callbackScheme, preferredBrowserSession: .shared)
            try await api.finishBrowserSignIn(callback, request: request)
            model.signedInAnew()
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            // Closed by the person: nothing to say.
        } catch {
            self.error = error.localizedDescription
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
