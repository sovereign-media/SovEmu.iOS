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

/// Systems whose picture keeps its own shape rather than a TV's 4:3.
private let handhelds: Set<String> = ["gb", "gbc", "gba", "gamegear"]

/// Seconds without a new video frame, while playing, before it is reported as a stall.
private let stallSeconds = 3

/// Where stats are turned on, and on the overlay: they cost a little every second.
private let statsWarning = "Showing stats can affect game performance."

/// Waits for Continue or Start over, when there is an auto save and the player was not asked yet.
@MainActor
@Observable
private final class Chooser {
    var asking = false
    @ObservationIgnored private var continuation: CheckedContinuation<Start, Never>?

    func ask() async -> Start {
        await withCheckedContinuation { c in
            continuation = c
            asking = true
        }
    }

    func choose(_ start: Start) {
        asking = false
        continuation?.resume(returning: start)
        continuation = nil
    }
}

/// The in-game menu's pages beyond the main one.
private enum MenuPage { case main, save, load, disc, cheats }

/// The player, as the Android app's: starts the session at once (following its progress on a
/// loading screen, and asking Continue or Start over when there is an auto save), streams it,
/// frames the picture with its decoration, and overlays a touch controller when there is nothing
/// else to play with. The in-game menu (the ☰ button, Select+Start, Home on a controller or
/// Escape) saves and loads by slot, changes disc, turns cheats on and off, remaps controllers,
/// shows the stats, and quits. However the player is left, the session is stopped (the worker
/// writes its saves first), even one still starting.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    let system: SystemSummary
    let game: Game
    let start: Start
    let onExit: () -> Void

    @State private var session: SessionInfo?
    @State private var stream: Stream?
    /// A failure to start, or a lost connection, shown in place of the game.
    @State private var error: String?
    /// The server's word on how far the start has got (nil until it has said), and the bar.
    @State private var progress: StartStatus?
    @State private var bar = 0.0
    @State private var pictureShown = false
    /// The worker's check of the connection before the stream starts (`0x83`), as it last said.
    @State private var link: WireProtocol.Link?
    /// The screenshot of the save being continued: the loading screen's background.
    @State private var saveShot: String?
    /// How long the ready session has waited for its first picture.
    @State private var waitedMs: Int64 = 0
    @State private var chooser = Chooser()
    @State private var startId = newStartId()
    @State private var starting: Task<SessionInfo, Error>?
    /// The stream has connected once: a failure after that is a lost connection.
    @State private var everConnected = false
    @State private var menuOpen = false
    @State private var menuPage = MenuPage.main
    @State private var slots: [SaveSlot]?
    @State private var cheats: [Cheat]?
    @State private var addingCheat = false
    @State private var cheatCode = ""
    @State private var cheatName = ""
    @State private var showTouch = !Self.hasInputDevice
    /// The disc in the tray after a change (a multi-disc game); the session says until then.
    @State private var disc: Int?
    @State private var toast: String?
    /// The stream's quality changed: the notice at the top of the screen, for a moment.
    @State private var quality: WireProtocol.QualityNotice?
    /// The stats overlay's rows (nil while it is off or has no sample yet) and its graph.
    @State private var statsRows: [(label: String, value: String)]?
    @State private var history = LatencyHistory()
    @State private var decoration: GameDecoration?
    @State private var controller = Controller()
    @State private var gameMenu: GameMenu?
    /// The system's buttons and pad, and the controllers' diagrams, for remapping.
    @State private var controls: ControlsInfo?
    @State private var video: RTCMTLVideoView = {
        let v = RTCMTLVideoView(frame: .zero)
        // The whole frame, stretched to the console's shape (the box it is in): never cropped.
        v.videoContentMode = .scaleToFill
        return v
    }()

    private static var hasInputDevice: Bool { !GCController.controllers().isEmpty || GCKeyboard.coalesced != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Decorated(decoration: decoration, aspect: aspect) { VideoView(view: video) }
                .ignoresSafeArea()
            if let screen = GameStart.screen(title: game.title, error: error, progress: progress, bar: bar, ready: session != nil,
                                             link: link, pictureShown: pictureShown, waitedMs: waitedMs)
                ?? (chooser.asking ? StartScreen(label: "") : nil) {
                Splash(game: game, system: system, screen: screen, chooser: chooser,
                       background: loadingBackground(saveShot: saveShot, image: game.image, boxArt: game.cover ?? game.thumb),
                       status: session.map { loadingStatus(core: $0.core, width: $0.width, height: $0.height, fps: $0.fps) } ?? "",
                       network: LinkLabels.networkLabel(link?.path ?? ""))
            }
            if showTouch && !menuOpen && session != nil && error == nil { TouchControls(controller: controller) }
            if let statsRows {
                StatsOverlay(rows: statsRows, history: history)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .allowsHitTesting(false)
            }
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
        .task { await begin() }
        .task(id: session?.id) { await pollProgress() }
        .task(id: stream != nil && !pictureShown && session != nil) { await countWait() }
        .task(id: stream != nil) { await watchForStalls() }
        .onChange(of: menuOpen) { _, open in
            stream?.suspended = open
            if !open { menuPage = .main }
        }
        .onChange(of: menuPage) { _, page in
            gameMenu?.focus = 0
            Task { await loadPage(page) }
        }
        .onChange(of: settings.stats) { _, on in
            history.clear()
            if !on { statsRows = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in showTouch = false }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in showTouch = false }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            // The touch controls come back once nothing else is left to play with.
            DispatchQueue.main.async { if !Self.hasInputDevice { showTouch = true } }
        }
        .onDisappear(perform: leave)
        .alert("Add a cheat", isPresented: $addingCheat) {
            TextField("Code (Game Genie, Action Replay, raw)", text: $cheatCode)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().fontDesign(.monospaced)
            TextField("Name (optional)", text: $cheatName)
            Button("Add") { addCheat() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The console's shape: 4:3 for a TV console, the screen's own for a handheld.
    private var aspect: CGFloat {
        if handhelds.contains(system.id), let s = session, s.height > 0 { return CGFloat(s.width) / CGFloat(s.height) }
        return 4 / 3
    }

    // MARK: The menu

    private var menu: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture { if gameMenu?.capture == nil { close() } }
            if let gameMenu {
                let items = gameMenu.items(main: pageItems, close: close)
                GameMenuView(
                    title: pageTitle, heading: gameMenu.heading, items: items,
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
                menu.poll(main: pageItems, close: close)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var pageTitle: String {
        switch menuPage {
        case .main: game.title
        case .save: "Save to a slot"
        case .load: "Load a save"
        case .disc: "Change disc"
        case .cheats: "Cheats"
        }
    }

    /// Back from a page returns to the main one; from the main one it resumes.
    private func close() {
        if menuPage != .main {
            menuPage = .main
            return
        }
        gameMenu?.markClosed()
        menuOpen = false
    }

    private var discs: Int { session?.discs ?? 1 }
    private var currentDisc: Int { disc ?? session?.disc ?? 1 }

    /// The rows of the page shown: the main page's, or a picker's.
    private var pageItems: [MenuItem] {
        switch menuPage {
        case .main: return mainItems
        case .save, .load:
            guard let slots else { return [MenuItem(id: "loading", title: "Loading saves…", action: {}, enabled: false)] }
            let saving = menuPage == .save
            let now = Int64(Date().timeIntervalSince1970)
            let rows = slotRows(slots, saving ? saveSlots : [autoSlot] + saveSlots, emptyEnabled: saving)
            return rows.map { row in
                MenuItem(
                    id: "slot\(row.slot)", title: row.label,
                    detail: row.save.map { "Saved " + formatAgo(Int64($0.savedAt), now: now) } ?? "Empty",
                    action: { saving ? save(to: row.slot) : load(from: row.slot) },
                    image: row.save?.screenshotUrl ?? "", enabled: row.enabled)
            } + [MenuItem(id: "back", title: "Back", action: { menuPage = .main })]
        case .disc:
            return (1...max(1, discs)).map { n in
                MenuItem(id: "disc\(n)", title: n == currentDisc ? "Disc \(n) · in the console" : "Disc \(n)") { change(disc: n) }
            } + [MenuItem(id: "back", title: "Back", action: { menuPage = .main })]
        case .cheats:
            guard let cheats else { return [MenuItem(id: "loading", title: "Loading cheats…", action: {}, enabled: false)] }
            var rows = cheats.map { cheat in
                MenuItem(
                    id: "cheat\(cheat.id)", title: cheat.description.isEmpty ? cheat.code : cheat.description,
                    detail: (cheat.description.isEmpty ? "" : cheat.code + "  ") + (cheat.enabled ? "On" : "Off"),
                    action: { toggle(cheat) },
                    adjust: { _ in toggle(cheat) },
                    onDelete: { delete(cheat) })
            }
            if cheats.isEmpty { rows.append(MenuItem(id: "none", title: "No cheats for this game yet.", action: {}, enabled: false)) }
            rows.append(MenuItem(id: "add", title: "Add a cheat…") {
                cheatCode = ""
                cheatName = ""
                addingCheat = true
            })
            rows.append(MenuItem(id: "back", title: "Back", action: { menuPage = .main }))
            return rows
        }
    }

    private var mainItems: [MenuItem] {
        var rows = [
            MenuItem(id: "resume", title: "Resume") { close() },
            MenuItem(id: "save", title: "Save state") { menuPage = .save },
            MenuItem(id: "load", title: "Load state") { menuPage = .load },
        ]
        if discs > 1 {
            rows.append(MenuItem(id: "disc", title: "Change disc", detail: "Disc \(currentDisc) of \(discs)") { menuPage = .disc })
        }
        rows += [
            MenuItem(id: "cheats", title: "Cheats") { menuPage = .cheats },
            MenuItem(id: "controllers", title: "Controllers", detail: "Players and buttons") { gameMenu?.showControllers() },
            MenuItem(id: "stats", title: settings.stats ? "Hide stats" : "Show stats", detail: statsWarning) {
                settings.stats.toggle()
            },
            MenuItem(id: "touch", title: showTouch ? "Hide touch controls" : "Show touch controls") {
                showTouch.toggle()
                close()
            },
            MenuItem(id: "quit", title: "Quit game") { onExit() },
        ]
        return rows
    }

    private func loadPage(_ page: MenuPage) async {
        guard let api = model.api else { return }
        switch page {
        case .save, .load:
            slots = nil
            slots = (try? await api.saves(gameId: game.id)) ?? []
        case .cheats:
            cheats = nil
            do {
                cheats = try await api.cheats(gameId: game.id)
            } catch {
                cheats = []
                flash("Could not load cheats: \(error.localizedDescription)")
            }
        default: break
        }
    }

    private func save(to slot: Int) {
        run("Saved to slot \(slot)", failed: "Save failed") { try await $0.saveState(sessionId: $1, slot: slot) }
    }

    private func load(from slot: Int) {
        let name = slot == autoSlot ? "the auto save" : "slot \(slot)"
        run("Loaded \(name)", failed: "Load failed") { try await $0.loadState(sessionId: $1, slot: slot) }
    }

    private func change(disc n: Int) {
        run("Disc \(n) is in", failed: "Could not change disc") { api, id in
            try await api.setDisc(sessionId: id, disc: n)
            await MainActor.run { disc = n }
        }
    }

    /// Runs a session action, says how it went, and resumes the game.
    private func run(_ done: String, failed: String, _ action: @escaping (SovEmuAPI, String) async throws -> Void) {
        guard let api = model.api, let session else { return }
        Task {
            do {
                try await action(api, session.id)
                flash(done)
            } catch {
                flash("\(failed): \(error.localizedDescription)")
            }
            menuPage = .main
            close()
        }
    }

    private func toggle(_ cheat: Cheat) {
        changeCheats { try await $0.setCheatEnabled(gameId: game.id, cheatId: cheat.id, enabled: !cheat.enabled) }
    }

    private func delete(_ cheat: Cheat) {
        changeCheats { api in
            try await api.deleteCheat(gameId: game.id, cheatId: cheat.id)
            return try await api.cheats(gameId: game.id)
        }
    }

    private func addCheat() {
        // Codes are upper case; the keyboard capitalises as it types, and this catches the rest.
        let code = cheatCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = cheatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        changeCheats { try await $0.addCheat(gameId: game.id, code: code, description: name) }
    }

    /// A change to the game's cheats (a running session applies it at once), then the list as it is.
    private func changeCheats(_ change: @escaping (SovEmuAPI) async throws -> [Cheat]) {
        guard let api = model.api else { return }
        Task {
            do {
                cheats = try await change(api)
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    // MARK: Starting and leaving

    private func begin() async {
        guard let api = model.api else { return }
        // Started at once: the question, the mappings and the decoration come meanwhile.
        let id = startId
        let gameId = game.id
        let task = Task { try await api.startSession(gameId: gameId, startId: id) }
        starting = task
        Task { decoration = try? await api.decoration(gameId: gameId) }
        controller.analogSticks = system.needsGpu
        async let config = try? api.config()
        async let mappings = try? Mappings.fetch(system: system.id, with: api)
        async let info = try? api.controls(system: system.id)
        do {
            var how = start
            // Nil when not asked for: a missing list only leaves the loading screen without the
            // save's screenshot, and asking treats it as no auto save.
            var saves: [SaveSlot]?
            if how == .ask {
                saves = try? await api.saves(gameId: game.id)
                how = (saves ?? []).contains { $0.slot == autoSlot } ? await chooser.ask() : .new
            }
            if case .fromSlot(let slot) = how { showSaveShot(slot: slot, saves: saves, api: api) }
            // The mappings in force on this system (and on every system, for remapping); a
            // model without one, or no answer, uses the built-in defaults.
            controller.mappings = await mappings ?? Mappings(system: system.id)
            controls = await info
            let started = try await task.value
            if case .fromSlot(let slot) = how {
                do {
                    try await api.loadState(sessionId: started.id, slot: slot)
                } catch {
                    flash("Could not load: \(error.localizedDescription)")
                }
            }
            session = started
            let s = Stream(api: api, sessionId: started.id, iceServers: await config?.iceServers ?? [], controller: controller,
                           videoView: video)
            s.onQuality = { showQuality($0) }
            s.onFirstFrame = { pictureShown = true }
            s.onLink = { l in
                link = l
                // A check started again (the selected pair changed) does not take the bar back.
                if l.state == WireProtocol.Link.probing { bar = max(bar, describeLink(l).fraction) }
            }
            s.onStats = { stats, reading in
                guard settings.stats else { return }
                statsRows = WireProtocol.overlayRows(stats, reading: reading, pipeline: s.pipeline, link: s.link)
                guard reading.hasVideo else { return }
                history.add(measured: stats.inputToFrameMs.map(Double.init), estimated: stats.estimateMs)
            }
            s.onState = { state in
                if state == .failed { error = "Connection failed" }
                if state == .connected { everConnected = true }
                if state == .failed || state == .disconnected {
                    let kind: ClientEventKind = everConnected ? .connectionLost : .connectionFailed
                    ClientEvents.report(kind, "WebRTC \(state == .failed ? "failed" : "disconnected")", sessionId: started.id)
                }
            }
            s.onMenu = {
                // The press that just closed the menu (Escape, Home) must not reopen it.
                if !menuOpen && Date().timeIntervalSince(gameMenu?.closedAt ?? .distantPast) > 0.3 { menuOpen = true }
            }
            stream = s
            try await s.connect()
        } catch is CancellationError {
        } catch {
            self.error = "Could not start: \(error.localizedDescription)"
        }
    }

    /// The screenshot of the save the game continues from, behind the loading screen: the auto
    /// save's comes with the game; another slot's from the list, fetched if it was not already.
    private func showSaveShot(slot: Int, saves: [SaveSlot]?, api: SovEmuAPI) {
        if slot == autoSlot, let shot = game.autoSave?.screenshotUrl {
            saveShot = shot
            return
        }
        if let saves {
            saveShot = saves.first { $0.slot == slot }?.screenshotUrl
            return
        }
        let gameId = game.id
        // Without the list the screen falls back to the game's own picture: nothing to report.
        Task { saveShot = (try? await api.saves(gameId: gameId))?.first { $0.slot == slot }?.screenshotUrl }
    }

    /// The start's progress, polled four times a second while the session starts. A failed poll
    /// keeps the last word; the bar only moves forward.
    private func pollProgress() async {
        guard session == nil, let api = model.api else { return }
        var forward = ForwardOnly()
        while !Task.isCancelled, session == nil, error == nil {
            if let status = try? await api.startProgress(startId: startId) {
                progress = status
                bar = forward.next(describeStart(status).fraction)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// How long the ready session has waited for its first picture.
    private func countWait() async {
        guard session != nil, !pictureShown else { return }
        let since = Date()
        while !Task.isCancelled, !pictureShown {
            waitedMs = Int64(Date().timeIntervalSince(since) * 1000)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// A picture that stops while playing (not paused in the menu) is reported once it has been
    /// still for `stallSeconds`. Before the first picture, the game is still starting.
    private func watchForStalls() async {
        guard let s = stream else { return }
        var last = s.frames
        var still = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let frames = s.frames
            let playing = everConnected && pictureShown && !menuOpen
            still = playing && frames == last ? still + 1 : 0
            last = frames
            if still == stallSeconds {
                ClientEvents.report(.streamStalled, "no new picture for \(stallSeconds) s", sessionId: session?.id)
            }
        }
    }

    /// Leaving, however it happens: the stream closes and the session stops once it has started
    /// (if it does), so its worker writes the saves and exits.
    private func leave() {
        stream?.close()
        controller.clear()
        guard let api = model.api, let starting else { return }
        Task.detached {
            if let started = try? await starting.value { try? await api.stopSession(started.id) }
        }
    }

    // MARK: Notices

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
}

/// The game's picture, `aspect` wide for its height, centred, and framed by its `decoration`
/// when it has one and the screen is wider than the picture: the artwork fitted to the screen,
/// the picture (its shape kept) in the artwork's window, the artwork drawn over its edges.
struct Decorated<Picture: View>: View {
    let decoration: GameDecoration?
    let aspect: CGFloat
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        GeometryReader { geo in
            let screen = geo.size.height > 0 ? geo.size.width / geo.size.height : aspect
            Group {
                if let d = decoration, shouldFrame(screenAspect: screen, pictureAspect: aspect) {
                    GeometryReader { box in
                        // The window, in this box's points: the image is scaled to exactly this box.
                        let sx = box.size.width / CGFloat(max(1, d.width))
                        let sy = box.size.height / CGFloat(max(1, d.height))
                        ZStack {
                            picture()
                                .aspectRatio(aspect, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.leading, sx * CGFloat(d.left)).padding(.trailing, sx * CGFloat(d.right))
                                .padding(.top, sy * CGFloat(d.top)).padding(.bottom, sy * CGFloat(d.bottom))
                            RemoteImage(path: d.url, contentMode: .fill).allowsHitTesting(false)
                        }
                    }
                    .aspectRatio(d.aspect, contentMode: .fit)
                } else {
                    picture().aspectRatio(aspect, contentMode: .fit)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// While the game loads, as the other clients' loading screen (#243, SovEmu.Web's
/// `LoadingScreen.tsx`, SovEmu.Android's `Splash`): a darkened picture behind, full bleed (the save
/// being continued, the game, its box blurred, or the system's colour), the bar dead centre with
/// what the start is doing, where the player is in a chip top right, the game bottom left, and a
/// spinner bottom right, which a failure replaces with the alert. Continue / Start over, when
/// asked, takes the bar's place.
private struct Splash: View {
    let game: Game
    let system: SystemSummary
    let screen: StartScreen
    let chooser: Chooser
    let background: LoadingBackground?
    /// `FCEUmm · 256×224 @ 60.10 fps`, once the emulator is up.
    let status: String
    /// `Home network` or `Remote`, once the worker has checked the connection.
    let network: String?

    /// A start that failed (or a lost connection): it has a line to say and no bar.
    private var failed: Bool { screen.fraction == nil && !screen.label.isEmpty }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            if chooser.asking {
                HStack(spacing: 8) {
                    Button { chooser.choose(.continue) } label: { Label("Continue", systemImage: "play.fill") }.buttonStyle(.sov())
                    Button { chooser.choose(.new) } label: { Label("Start over", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.sov(.outline))
                }
                .padding(24)
            } else {
                progress.padding(.horizontal, 24)
            }
            if let network {
                Text(network).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sov.slate100)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(24)
            }
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    SystemBadge(short: system.short, colour: system.accent)
                    Text(game.title).font(.system(size: 32, weight: .black)).foregroundStyle(.white).lineLimit(1)
                    if !status.isEmpty {
                        Text(status).font(.system(size: 14)).monospacedDigit().foregroundStyle(Sov.slate300)
                    }
                }
                Spacer(minLength: 0)
                if failed {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 36)).foregroundStyle(Sov.red300)
                } else {
                    ProgressView().controlSize(.large).tint(.white.opacity(0.8))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(24)
        }
    }

    /// The picture, then an even black scrim at 55%, deepening to about 80% along the bottom
    /// where the text and the spinner sit.
    private var backdrop: some View {
        ZStack {
            Sov.surface
            if let background {
                RemoteImage(path: background.url, pixelated: background.pixelated)
                    .blur(radius: background.blurred ? 24 : 0)
                    .scaleEffect(background.blurred ? 1.1 : 1)
            } else {
                tile(system.accent, mix: 0.25)
            }
            Color.black.opacity(0.55)
            GeometryReader { geo in
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: geo.size.height * 0.4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipped()
    }

    /// The bar, what the start is doing, its detail and how to reach the menu, dead centre.
    private var progress: some View {
        VStack(spacing: 12) {
            if let fraction = screen.fraction {
                ProgressView(value: fraction).progressViewStyle(.linear).tint(Sov.accent).frame(maxWidth: 400)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
            Text(screen.label).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(failed ? Sov.red300 : Sov.slate100).multilineTextAlignment(.center)
            if !screen.detail.isEmpty {
                Text(screen.detail).font(.system(size: 16)).monospacedDigit().foregroundStyle(Sov.slate300)
                    .multilineTextAlignment(.center)
            }
            Text(loadingHint).font(.system(size: 13)).foregroundStyle(Sov.slate400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Latency and stream health over the game, as the other clients': its rows in two columns
/// above a graph of the last minute's latency. It never takes a touch.
private struct StatsOverlay: View {
    let rows: [(label: String, value: String)]
    let history: LatencyHistory

    var body: some View {
        let half = (rows.count + 1) / 2
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 20) {
                column(Array(rows.prefix(half)))
                column(Array(rows.dropFirst(half)))
            }
            LatencyGraph(history: history).frame(height: 64)
            Text(statsWarning).font(.system(size: 10)).foregroundStyle(Sov.slate400)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func column(_ rows: [(label: String, value: String)]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) { ForEach(rows, id: \.label) { Text($0.label).foregroundStyle(Sov.slate400) } }
            VStack(alignment: .trailing, spacing: 1) { ForEach(rows, id: \.label) { Text($0.value).foregroundStyle(.white) } }
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

/// The last minute of "Measured button→frame" (solid, accent) and "Estimated button→pixel"
/// (thin, muted), from 0 to the history's scale, with its gridlines and the latest measurement
/// at the right.
private struct LatencyGraph: View {
    let history: LatencyHistory

    var body: some View {
        Canvas { context, size in
            let top = history.scaleMaxMs()
            let latest = history.latestMeasured.map { Text("\(Int($0.rounded())) ms").font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Sov.accent) }
            let latestWidth: CGFloat = latest == nil ? 0 : 44
            let right = size.width - latestWidth - 4
            func y(_ ms: Double) -> CGFloat { size.height * (1 - ms / top) }
            for ms in [top, top / 2] {
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(ms))); $0.addLine(to: CGPoint(x: right, y: y(ms))) },
                               with: .color(Sov.edge), lineWidth: 1)
                context.draw(Text("\(Int(ms.rounded()))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Sov.slate500),
                             at: CGPoint(x: 0, y: y(ms)), anchor: .topLeading)
            }
            let step = right / CGFloat(history.capacity - 1)
            // Newest at the right edge; a minute's worth fills the width.
            let first = history.capacity - history.size
            func trace(_ value: (Int) -> Double) -> Path {
                var path = Path()
                var pen = false
                for i in 0..<history.size {
                    let v = value(i)
                    guard !v.isNaN else {
                        pen = false
                        continue
                    }
                    let point = CGPoint(x: CGFloat(first + i) * step, y: y(v))
                    if pen { path.addLine(to: point) } else { path.move(to: point) }
                    pen = true
                }
                return path
            }
            context.stroke(trace(history.estimated), with: .color(Sov.slate400), lineWidth: 1)
            context.stroke(trace(history.measured), with: .color(Sov.accent), lineWidth: 2)
            if let latest, let v = history.latestMeasured {
                context.draw(latest, at: CGPoint(x: size.width, y: min(max(y(v), 6), size.height - 6)), anchor: .trailing)
            }
        }
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
