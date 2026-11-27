// Signing in on the TV, as SovEmu.Android's TV app (`feature-tv`'s `Login.kt`, over
// `core/SignInFlow.kt`) and Sovereign's TVs: the server's address first (https, then http
// unless *Secure connections only*), then *Sign in with your phone* (a code and its QR code to
// approve on a signed-in phone or browser) with the password as the fallback, and only the code
// when the server has the password off. Text is typed with tvOS's own keyboard. What a sign-in
// gets is kept by `TVSession.signedIn`, keyed on the ID token's `sub`.
import SovEmuKit
import SwiftUI


struct SignInFormPage: View {
    @Environment(TVSession.self) private var session
    /// *Add a user*, from the picker.
    var addUser = false
    /// The username filled in after a sign-in ended.
    var username = ""
    /// Why the form is up (a sign-in that ended).
    var notice: String?
    /// *Add a server*: an empty address, the stored one not asked.
    var newServer = false
    /// *Choose a server*, when the device holds other accounts (nil: not offered).
    var onChangeServer: (() -> Void)?
    let onCustomHeaders: () -> Void

    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    /// How to sign in at the server: nil until an address has been checked.
    @State private var config: BootstrapConfig?
    @State private var error: String?
    @State private var busy = false
    /// The code, asked for (or the only way in).
    @State private var pairingAsked = false
    /// The client signing in, made once the server's answer is in.
    @State private var pending: PendingSignIn?
    @State private var started = false
    @FocusState private var focus: LaunchFocus?

    private var ready: Bool { config != nil && config?.signInProblem == nil }
    private var pairing: Bool {
        guard ready, let config, config.canPair else { return false }
        return pairingAsked || !config.canUsePassword
    }

    var body: some View {
        Group {
            if pairing, let pending, let config {
                PairingPage(
                    api: pending.api,
                    onApproved: { try await session.signedIn(pending) },
                    onUsePassword: config.canUsePassword ? { pairingAsked = false } : nil,
                    onChangeServer: {
                        pairingAsked = false
                        forgetServer()
                    })
            } else {
                form
                    // The first field to fill: the username once the server is known.
                    .defaultFocus($focus, ready ? .username : .server)
                    // A page put in place of another can be left with nothing focused (tvOS
                    // does not move the focus off a view that went): take it.
                    .task {
                        try? await Task.sleep(for: .milliseconds(100))
                        if focus == nil { focus = ready ? .username : .server }
                    }
            }
        }
        .task {
            guard !started else { return }
            started = true
            user = username
            let model = session.model
            server = newServer ? "" : model.serverURL
            // A stored address is asked again each time the form opens, so its details stay current.
            if !newServer, !model.serverURL.isEmpty {
                config = model.bootstrap
                pending = session.pendingSignIn()
                await check(model.serverURL, quiet: true)
            }
        }
    }

    // MARK: The form

    private var form: some View {
        LaunchBackdrop {
            LaunchCard {
                VStack(alignment: .leading, spacing: 4 * launchDp) {
                    LaunchBrand(size: 30)
                    Text(addUser ? LaunchText.addAUser : "Sign in to play.")
                        .font(.system(size: 14 * launchDp)).foregroundStyle(launchMuted)
                }
                LaunchField("Server address", text: $server, content: .URL, keyboard: .URL, focus: $focus, tag: .server)
                    .onChange(of: server) { _, typed in
                        // Editing the address undoes its check; the address in use stays checked.
                        if !ServerAddress.names(typed, server: session.model.serverURL) { forgetServer() }
                    }
                if !ready {
                    LaunchToggle(title: "Secure connections only", on: session.secureOnly) {
                        session.secureOnly.toggle()
                        error = nil
                    }
                    Button(session.headers.isEmpty ? CustomHeadersText.title : "\(CustomHeadersText.title) (\(session.headers.count))",
                           action: onCustomHeaders)
                        .buttonStyle(.launch(.ghost, fill: true))
                        .disabled(busy)
                }
                if ready {
                    LaunchField("Username", text: $user, content: .username, keyboard: .emailAddress, focus: $focus, tag: .username)
                        .onChange(of: user) { error = nil }
                    LaunchField("Password", text: $password, secret: true, content: .password, focus: $focus, tag: .password)
                        .onChange(of: password) { error = nil }
                }
                if let notice, error == nil {
                    Text(notice).font(.system(size: 14 * launchDp)).foregroundStyle(Sov.slate300)
                }
                if let error { LaunchErrorLine(error) }
                Button { Task { await submit() } } label: {
                    Label(buttonTitle, systemImage: "arrow.right.to.line")
                }
                .buttonStyle(.launch(fill: true))
                .disabled(busy)
                if ready, config?.canPair == true {
                    Button {
                        pairingAsked = true
                        error = nil
                    } label: {
                        Label(PairingText.useCode, systemImage: "iphone")
                    }
                    .buttonStyle(.launch(.outline, fill: true))
                    .disabled(busy)
                }
                if let onChangeServer {
                    Button(action: onChangeServer) { Label(LaunchText.changeServer, systemImage: "server.rack") }
                        .buttonStyle(.launch(.ghost, fill: true))
                        .disabled(busy)
                }
            }
        }
    }

    private var buttonTitle: String {
        switch (ready, busy) {
        case (false, true): "Checking…"
        case (false, false): "Continue"
        case (true, true): "Signing in…"
        case (true, false): "Sign in"
        }
    }

    // MARK: Signing in

    /// The address being edited: what was checked no longer applies.
    private func forgetServer() {
        guard config != nil || error != nil else { return }
        config = nil
        error = nil
    }

    /// The button: checks the address typed while it is new (or not yet checked), else signs in
    /// with the password.
    private func submit() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        if !ready || !ServerAddress.names(server, server: session.model.serverURL) {
            await check(server)
            return
        }
        guard let pending else { return }
        do {
            try await pending.api.signIn(username: user.trimmingCharacters(in: .whitespaces), password: password)
            try await session.signedIn(pending)
        } catch {
            self.error = Self.message(error)
        }
    }

    /// Asks `input` how to sign in (`ServerAddress.check`); the first address that answers is
    /// kept as the server. `quiet` keeps a failure off the screen (on opening).
    private func check(_ input: String, quiet: Bool = false) async {
        do {
            switch try await ServerAddress.check(input, secureOnly: quiet ? false : session.secureOnly, service: session) {
            case let .answered(address, answer):
                config = answer
                error = answer.signInProblem
                if answer.signInProblem == nil, (try? await session.model.api?.status().setupRequired) == true {
                    config = nil
                    error = "Finish first-run setup in a browser at \(address) first."
                    return
                }
                // The field keeps what was typed; the server is the address that answered.
                pending = session.pendingSignIn()
            case let .failed(message):
                if !quiet { error = message }
            }
        } catch {
            // Cancelled: the form went away.
        }
    }

    /// The server's own words (wrong password, wait N minutes …) as they are; else unreachable.
    static func message(_ error: Error) -> String {
        if let error = error as? AuthError, let text = error.errorDescription { return text }
        if let error = error as? APIError { return error.message }
        return "Cannot reach the server: \(error.localizedDescription)"
    }
}

// MARK: - Sign in with your phone

/// The code to approve, where to approve it (also as a QR code), and how long it has left.
/// Waiting is the normal state, not an error, and is never shown as one. Leaving the page stops
/// the poll. `onUsePassword` is nil when the server has no password sign-in.
struct PairingPage: View {
    let api: SovEmuAPI
    let onApproved: () async throws -> Void
    let onUsePassword: (() -> Void)?
    let onChangeServer: () -> Void

    private enum Phase: Equatable {
        case asking
        /// `deadline` on `ProcessInfo.systemUptime`; `trouble`: the last poll got no answer.
        case showing(DeviceCode, deadline: TimeInterval, trouble: Bool)
        case failed(String)
    }

    @State private var phase = Phase.asking
    @State private var attempt = 0
    @FocusState private var focus: Int?

    var body: some View {
        LaunchBackdrop {
            LaunchCard(width: 640, spacing: 20) {
                Text(PairingText.title).font(.system(size: 24 * launchDp, weight: .semibold)).foregroundStyle(.white)
                switch phase {
                case .asking:
                    Text(PairingText.asking).font(.system(size: 16 * launchDp)).foregroundStyle(launchMuted)
                case let .showing(code, deadline, trouble):
                    showing(code, deadline: deadline, trouble: trouble)
                case let .failed(message):
                    LaunchErrorLine(message)
                }
                VStack(spacing: 8 * launchDp) {
                    if case .failed = phase {
                        Button { attempt += 1 } label: { Label(PairingText.newCode, systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.launch(fill: true))
                            .focused($focus, equals: 0)
                    }
                    if let onUsePassword {
                        Button(action: onUsePassword) { Label(PairingText.usePassword, systemImage: "arrow.right.to.line") }
                            .buttonStyle(.launch(.outline, fill: true))
                            .focused($focus, equals: 1)
                    }
                    Button(action: onChangeServer) { Label(LaunchText.changeServer, systemImage: "server.rack") }
                        .buttonStyle(.launch(.ghost, fill: true))
                        .focused($focus, equals: 2)
                }
            }
        }
        .defaultFocus($focus, onUsePassword != nil ? 1 : 2)
        .task(id: attempt) { await pair() }
    }

    private func showing(_ code: DeviceCode, deadline: TimeInterval, trouble: Bool) -> some View {
        HStack(alignment: .center, spacing: 28 * launchDp) {
            VStack(alignment: .leading, spacing: 8 * launchDp) {
                Text(PairingText.goTo).font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate300)
                Text(code.shownURI).font(.system(size: 20 * launchDp, weight: .semibold)).foregroundStyle(.white)
                Text(PairingText.enter).font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate300).padding(.top, 8 * launchDp)
                Text(code.grouped).font(.system(size: 40 * launchDp, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .fixedSize()
                    .accessibilityLabel(code.grouped.map(String.init).joined(separator: " "))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let left = deadline - ProcessInfo.processInfo.systemUptime
                    Text("\(trouble ? PairingText.trouble : PairingText.waiting) · \(PairingText.expiresIn(left))")
                        .font(.system(size: 14 * launchDp)).foregroundStyle(trouble ? Sov.amber200 : launchMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            QRCodeImage(text: code.qrContent)
                .frame(width: 168 * launchDp, height: 168 * launchDp)
                .accessibilityLabel("QR code for \(code.qrContent)")
        }
    }

    /// Asks for a code, then waits for its approval: signed in, or why not.
    private func pair() async {
        phase = .asking
        let code: DeviceCode
        do {
            code = try await api.requestDeviceCode()
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(SignInFormPage.message(error))
            return
        }
        let deadline = ProcessInfo.processInfo.systemUptime + code.expiresIn
        phase = .showing(code, deadline: deadline, trouble: false)
        do {
            let result = try await awaitApproval(
                code,
                poll: { try await api.pollDeviceCode(code) },
                now: { ProcessInfo.processInfo.systemUptime },
                sleep: { try await Task.sleep(for: .seconds($0)) },
                reachable: { ok in
                    Task { @MainActor in
                        if case let .showing(c, d, _) = phase { phase = .showing(c, deadline: d, trouble: !ok) }
                    }
                })
            switch result {
            case .approved:
                do {
                    try await onApproved()
                } catch {
                    phase = .failed(SignInFormPage.message(error))
                }
            case let .failed(failure):
                phase = .failed(failure.message)
            }
        } catch {
            // Cancelled: the page went away, or a new code was asked for.
        }
    }
}
