import GameController
import SwiftUI
import SovEmuKit
import WebRTC

/// The stream's video view.
struct VideoView: UIViewRepresentable {
    let view: RTCMTLVideoView

    func makeUIView(context: Context) -> RTCMTLVideoView { view }
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
}

/// The player: starts the session, streams it and overlays a touch controller. The in-game
/// menu (the ☰ button, Select+Start, Home on a controller or Escape) saves, loads, remaps
/// controllers, moves them between players, and quits; a controller drives it as well as touch.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    let system: SystemSummary
    let game: Game
    let onExit: () -> Void

    @State private var session: SessionInfo?
    @State private var stream: Stream?
    @State private var status = "Starting…"
    /// The stream has connected once: a failure after that is a lost connection.
    @State private var everConnected = false
    @State private var menuOpen = false
    @State private var showTouch = GCController.controllers().isEmpty
    /// The disc in the tray after a change (a multi-disc game); the session says until then.
    @State private var disc: Int?
    @State private var toast: String?
    /// The stream's quality changed: the notice at the top of the screen, for a moment.
    @State private var quality: WireProtocol.QualityNotice?
    @State private var controller = Controller()
    @State private var gameMenu: GameMenu?
    /// The system's buttons and pad, and the controllers' diagrams, for remapping.
    @State private var controls: ControlsInfo?
    @State private var video: RTCMTLVideoView = {
        let v = RTCMTLVideoView(frame: .zero)
        v.videoContentMode = .scaleAspectFit
        return v
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoView(view: video).ignoresSafeArea()
            if !status.isEmpty {
                VStack(spacing: 12) {
                    if status.hasPrefix("Starting") { ProgressView() }
                    Text(status).foregroundStyle(.white)
                }
            }
            if showTouch && !menuOpen { TouchControls(controller: controller) }
            VStack {
                HStack {
                    Spacer()
                    Button { menuOpen = true } label: {
                        Image(systemName: "line.3.horizontal").font(.title2).padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                if let toast {
                    Text(toast).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.black.opacity(0.8), in: Capsule()).padding(.bottom, 24)
                }
            }
            .padding()
            // Sovereign's player message chip (a glyph before the line, gray-950 at 75% under a
            // 2 pt white/40 edge, two lines at most), but at the very top edge of the screen
            // rather than 12% down, so it stays out of the game.
            if let quality {
                VStack {
                    HStack(spacing: 8) {
                        if let symbol = Self.qualitySymbols[quality.icon] { Image(systemName: symbol) }
                        Text(quality.line).lineLimit(2)
                    }
                    .font(.body).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(minHeight: 40)
                    .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255).opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.4), lineWidth: 2))
                    .frame(maxWidth: 560)
                    Spacer()
                }
                .padding(.top, 8).padding(.horizontal, 16)
                .allowsHitTesting(false)
            }
            if menuOpen { menu }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .onChange(of: menuOpen) { _, open in stream?.suspended = open }
        .onDisappear { stream?.close() }
    }

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture { if gameMenu?.capture == nil { closeMenu() } }
            if let gameMenu {
                let items = gameMenu.items(main: mainItems, close: closeMenu)
                GameMenuView(
                    title: game.title, heading: gameMenu.heading, items: items,
                    focus: Binding(get: { gameMenu.focus }, set: { gameMenu.focus = $0 }),
                    diagrams: gameMenu.diagrams(items),
                    prompt: gameMenu.capturePrompt, onCancelCapture: gameMenu.cancelCapture)
                    .padding()
            }
        }
        .task {
            // Controller navigation: poll about every frame while the menu is open.
            let menu = gameMenu ?? GameMenu(controller: controller)
            menu.api = model.api
            menu.flash = { flash($0) }
            if menu.system.id != system.id { menu.system = (system.id, system.short) }
            menu.info = controls
            menu.open()
            gameMenu = menu
            while !Task.isCancelled {
                menu.poll(main: mainItems, close: closeMenu)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var mainItems: [MenuItem] {
        [
            MenuItem(id: "resume", title: "Resume") { closeMenu() },
            MenuItem(id: "save", title: "Save state (slot 1)") { Task { await run("Saved") { try await $0.saveState(sessionId: $1, slot: 1) } } },
            MenuItem(id: "load", title: "Load state (slot 1)") { Task { await run("Loaded") { try await $0.loadState(sessionId: $1, slot: 1) } } },
            MenuItem(id: "continue", title: "Continue from auto save") {
                Task { await run("Continued") { try await $0.loadState(sessionId: $1, slot: 0) } }
            },
        ] + discItems + [
            MenuItem(id: "controllers", title: "Controllers", detail: "Players and buttons") { gameMenu?.showControllers() },
            MenuItem(id: "touch", title: showTouch ? "Hide touch controls" : "Show touch controls") {
                showTouch.toggle()
                closeMenu()
            },
            MenuItem(id: "quit", title: "Quit game") { Task { await quit() } },
        ]
    }

    /// A multi-disc game: Change disc moves to the next disc (after the last, the first).
    private var discItems: [MenuItem] {
        let discs = session?.discs ?? 1
        guard discs > 1 else { return [] }
        let current = disc ?? session?.disc ?? 1
        let next = current % discs + 1
        return [
            MenuItem(id: "disc", title: "Change disc", detail: "Disc \(current) of \(discs) · next: disc \(next)") {
                Task {
                    await run("Disc \(next) is in") { try await $0.setDisc(sessionId: $1, disc: next) }
                    disc = next
                }
            },
        ]
    }

    private func closeMenu() {
        gameMenu?.markClosed()
        menuOpen = false
    }

    private func run(_ done: String, _ action: (SovEmuAPI, String) async throws -> Void) async {
        guard let api = model.api, let session else { return }
        do {
            try await action(api, session.id)
            flash(done)
        } catch {
            flash(error.localizedDescription)
        }
        closeMenu()
    }

    /// The system's nearest symbols to the notice's glyphs (Sovereign.Design's own `wifi-alert`
    /// and `wifi-up` are not system symbols); a name not here draws none.
    private static let qualitySymbols = ["wifi-alert": "wifi.exclamationmark", "wifi-up": "wifi", "gauge": "speedometer"]

    /// Shown for Sovereign's 5 s.
    private func showQuality(_ notice: WireProtocol.QualityNotice) {
        quality = notice
        Task {
            try? await Task.sleep(for: .seconds(5))
            if quality == notice { quality = nil }
        }
    }

    private func flash(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }

    private func start() async {
        guard let api = model.api else { return }
        do {
            let config = try? await api.config()
            let info = try await api.startSession(gameId: game.id)
            session = info
            controller.analogSticks = system.needsGpu
            // The mappings in force on this system (and on every system, for remapping); a model
            // without one, or no answer, uses the built-in defaults.
            controller.mappings = (try? await Mappings.fetch(system: system.id, with: api)) ?? Mappings(system: system.id)
            controls = try? await api.controls(system: system.id)
            let s = Stream(api: api, sessionId: info.id, iceServers: config?.iceServers ?? [], controller: controller, videoView: video)
            s.onQuality = { showQuality($0) }
            s.onState = { state in
                if state == .failed { status = "Connection failed" }
                if state == .connected { everConnected = true }
                if state == .failed || state == .disconnected {
                    let kind: ClientEventKind = everConnected ? .connectionLost : .connectionFailed
                    ClientEvents.report(kind, "WebRTC \(state == .failed ? "failed" : "disconnected")", sessionId: info.id)
                }
            }
            s.onMenu = {
                // The press that just closed the menu (Escape, Home) must not reopen it.
                if !menuOpen && Date().timeIntervalSince(gameMenu?.closedAt ?? .distantPast) > 0.3 { menuOpen = true }
            }
            stream = s
            try await s.connect()
            status = ""
        } catch {
            status = "Could not start: \(error.localizedDescription)"
        }
    }

    private func quit() async {
        stream?.close()
        if let api = model.api, let session { try? await api.stopSession(session.id) }
        controller.clear()
        onExit()
    }
}

/// An on-screen pad: D-pad bottom left, face buttons bottom right, Select/Start centre, L/R top.
struct TouchControls: View {
    let controller: Controller

    var body: some View {
        VStack {
            HStack {
                pad("L", .l, width: 88, height: 40)
                Spacer()
                pad("R", .r, width: 88, height: 40)
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    pad("▲", .up)
                    HStack(spacing: 56) { pad("◀", .left); pad("▶", .right) }
                    pad("▼", .down)
                }
                Spacer()
                HStack(spacing: 16) { pad("Select", .select, width: 72, height: 32); pad("Start", .start, width: 72, height: 32) }
                Spacer()
                VStack(spacing: 0) {
                    pad("X", .x, round: true)
                    HStack(spacing: 56) { pad("Y", .y, round: true); pad("A", .a, round: true) }
                    pad("B", .b, round: true)
                }
            }
        }
        .padding(24)
    }

    private func pad(_ label: String, _ button: RetroButton, round: Bool = false, width: CGFloat = 56, height: CGFloat = 56) -> some View {
        PadButton(label: label, round: round, width: width, height: height) { controller.setTouch(button, $0) }
    }
}

private struct PadButton: View {
    let label: String
    let round: Bool
    let width: CGFloat
    let height: CGFloat
    let onPress: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: width, height: height)
            .background(.white.opacity(pressed ? 0.45 : 0.18), in: RoundedRectangle(cornerRadius: round ? height / 2 : 10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onPress(true)
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onPress(false)
                    },
            )
    }
}
