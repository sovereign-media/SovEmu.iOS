// The TV's launch screens, as SovEmu.Android's (`feature/ui/Launch.kt`'s `LaunchScreens`, drawn
// by `feature-tv`'s `TvLaunchPages`): *Who's watching?*, *Choose a server*, the proxy headers
// and the sign-in form, each over the last; Back goes down the stack. `RootView` shows them
// while nobody is signed in; *Change user or server* opens them over the app
// (`launchScreens(_:)`). Where each choice leads is `TVSession`'s.
import SovEmuKit
import SwiftUI

struct ConnectView: View {
    @Environment(TVSession.self) private var session
    /// Opened from the account menu: the account signed in now is marked, and choosing it, or
    /// Back at the bottom, goes back to the app.
    var fromAccount = false
    @State private var stack: [LaunchPage] = []
    @State private var serverError: String?
    @State private var serverBusy = false

    var body: some View {
        ZStack {
            if session.switching || stack.isEmpty {
                LaunchBackdrop { EmptyView() }
            } else if let top = stack.last {
                page(top).id(stack)
            }
        }
        .background(Sov.surface.ignoresSafeArea())
        // Before `onAppear`: switching Back on and off makes what is inside afresh, which must
        // not start the stack again.
        .modifier(BackPops(active: stack.count > 1 || fromAccount, pop: pop))
        .onAppear { stack = session.startPages() }
        .onChange(of: session.landings) { stack = session.startPages() }
    }

    @ViewBuilder private func page(_ page: LaunchPage) -> some View {
        let model = session.model
        switch page {
        case .picker:
            let current = session.current?.id
            WhoIsWatchingPage(
                accounts: session.accountsHere,
                server: model.serverURL,
                focusOn: fromAccount ? current : session.accountsHere.max { $0.lastUsedAt < $1.lastUsedAt }?.id,
                current: fromAccount ? current : nil,
                onChoose: { session.choose($0) },
                onAddUser: { stack.append(.signIn(addUser: true)) },
                onChangeServer: { open(.servers) })
        case .servers:
            ChooseServerPage(
                servers: session.servers, error: serverError, busy: serverBusy,
                onChoose: { server in act { try await ServerChooser(service: session, session: session).choose(server) } },
                onRemove: { server in
                    let servers = session.servers
                    act { try await ServerChooser(service: session, session: session).remove(server, from: servers) }
                },
                onAddServer: { stack.append(.signIn(newServer: true, returnTo: model.serverURL)) })
        case .headers:
            CustomHeadersPage(headers: Binding(get: { session.headers }, set: { session.headers = $0 }), onDone: pop)
        case let .signIn(addUser, username, expired, newServer, _):
            SignInFormPage(
                addUser: addUser, username: username, notice: expired ? LaunchText.expired : nil, newServer: newServer,
                onChangeServer: !newServer && !addUser && !session.accounts.isEmpty ? { open(.servers) } : nil,
                onCustomHeaders: { stack.append(.headers) })
        }
    }

    private func open(_ page: LaunchPage) {
        serverError = nil
        stack.append(page)
    }

    private func pop() {
        if case let .signIn(_, _, _, true, returnTo?) = stack.last, session.model.serverURL != returnTo {
            // A new address was tried and abandoned: the server it replaced comes back.
            session.model.serverURL = returnTo
            Task { _ = try? await session.model.refreshBootstrap() }
        }
        if stack.count > 1 {
            stack.removeLast()
        } else if fromAccount {
            session.overApp = false
        }
    }

    /// Chooses or removes a server, one at a time, and goes where it left the app.
    private func act(_ move: @escaping () async throws -> ServerMove) {
        guard !serverBusy else { return }
        serverBusy = true
        serverError = nil
        Task {
            let moved = (try? await move()) ?? .stayed
            serverBusy = false
            switch moved {
            case .stayed:
                if stack.last == .servers { pop() }
            case .moved(let landing):
                stack = [landing == .login ? .signIn() : .picker]
            case .noServer:
                stack = [.signIn(newServer: true)]
            case .failed(let message):
                serverError = message
            }
        }
    }
}

/// Back pops the stack, when there is somewhere to go back to; at the bottom of the launch
/// screens on their own, Back leaves the app as usual.
private struct BackPops: ViewModifier {
    let active: Bool
    let pop: () -> Void

    func body(content: Content) -> some View {
        if active { content.onExitCommand(perform: pop) } else { content }
    }
}

extension View {
    /// The launch screens over the app (*Change user or server*), and the idle picker: the TV
    /// app's root wears this.
    func launchScreens(_ session: TVSession) -> some View {
        modifier(LaunchScreensOverApp(session: session))
    }
}

private struct LaunchScreensOverApp: ViewModifier {
    @Bindable var session: TVSession
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $session.overApp) {
                ConnectView(fromAccount: true)
                    .environment(session)
                    .environment(session.model)
            }
            .onChange(of: phase) { _, phase in session.scenePhase(phase) }
    }
}
