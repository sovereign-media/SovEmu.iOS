// Signing in on a TV, as SovEmu.Android's TV app (`Login.kt`) and Sovereign's TVs: the server's
// address first (https, then http unless *Secure connections only*), then *Sign in with your
// phone* (a code and its QR code to approve on a signed-in phone or browser) with the password as
// the fallback, and only the code when the server has the password off. Text is typed with
// tvOS's own keyboard.
import SwiftUI
import SovEmuKit

struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @AppStorage("secureOnly") private var secureOnly = true
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    /// The server's `bootstrapConfig`, once an address has answered.
    @State private var connected: BootstrapConfig?
    /// The password form, asked for instead of the code.
    @State private var passwordAsked = false

    var body: some View {
        ZStack {
            Sov.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    Image("SovEmuMark").resizable().scaledToFit().frame(height: 72).foregroundStyle(Sov.accent)
                    Text("SovEmu").font(.system(size: 64, weight: .black))
                }
                if let connected {
                    signIn(connected)
                } else {
                    serverForm
                }
                if let error { Text(error).foregroundStyle(Sov.red300) }
            }
            .padding(60)
            .frame(width: 1000)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 28))
        }
        .onAppear {
            address = Self.shown(model.serverURL)
            connected = model.bootstrap
        }
    }

    // MARK: The server

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sign in to play.").foregroundStyle(.secondary)
            TextField("Server address", text: $address)
                .textContentType(.URL)
                .autocorrectionDisabled()
            Toggle("Secure connections only", isOn: $secureOnly)
            Button(busy ? "Connecting…" : "Continue") { Task { await connect() } }
                .disabled(busy || address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// The address without its scheme, as it is typed.
    private static func shown(_ url: String) -> String {
        guard let range = url.range(of: "://") else { return url }
        return String(url[range.upperBound...])
    }

    /// The addresses to try for what was typed: as typed when it has a scheme, else https and,
    /// unless only secure connections are allowed, http after it.
    private func candidates() -> [String] {
        let typed = address.trimmingCharacters(in: .whitespaces)
        if typed.contains("://") { return [typed] }
        return secureOnly ? ["https://\(typed)"] : ["https://\(typed)", "http://\(typed)"]
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        error = nil
        let previous = model.serverURL
        var last: Error?
        for candidate in candidates() {
            model.serverURL = candidate
            guard model.api != nil else { continue }
            do {
                let config = try await model.refreshBootstrap()
                if config.signInProblem == nil, try await model.api?.status().setupRequired == true {
                    error = "Finish first-run setup in a browser at \(candidate) first."
                    return
                }
                connected = config
                passwordAsked = !config.canPair
                return
            } catch {
                last = error
            }
        }
        // An address that never answers puts the previous one back.
        model.serverURL = previous
        error = "No SovEmu server answered at \(address)" + (last.map { ": \($0.localizedDescription)" } ?? ".")
    }

    // MARK: Signing in

    @ViewBuilder private func signIn(_ config: BootstrapConfig) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(model.serverURL).foregroundStyle(.secondary)
            if let problem = config.signInProblem {
                Text(problem)
            } else if let api = model.api, config.canPair, !passwordAsked {
                PairingView(
                    api: api,
                    onSignedIn: { model.signedInAnew() },
                    onUsePassword: config.canUsePassword ? { passwordAsked = true; error = nil } : nil)
            } else if config.canUsePassword {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button(busy ? "Signing in…" : "Sign in") { Task { await signIn() } }
                    .disabled(busy || username.isEmpty || password.isEmpty)
                if config.canPair {
                    Button { passwordAsked = false; error = nil } label: {
                        Label(PairingText.title, systemImage: "iphone")
                    }
                }
            }
            Button("Change server") {
                connected = nil
                error = nil
            }
        }
    }

    private func signIn() async {
        guard let api = model.api else { return }
        busy = true
        defer { busy = false }
        error = nil
        do {
            try await api.signIn(username: username, password: password)
            model.signedInAnew()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
