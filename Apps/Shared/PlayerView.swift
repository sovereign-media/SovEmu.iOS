import GameController
import SwiftUI
import SovEmuKit
import WebRTC

/// The stream's video view.
struct VideoView: UIViewRepresentable {
    let view: SampleBufferVideoView

    func makeUIView(context: Context) -> SampleBufferVideoView { view }
    func updateUIView(_ uiView: SampleBufferVideoView, context: Context) {}
}

/// Systems whose picture keeps its own shape rather than a TV's 4:3.
private let handhelds: Set<String> = ["gb", "gbc", "gba", "gamegear"]

/// Seconds without a new video frame, while playing, before it is reported as a stall.
private let stallSeconds = 3

/// Where stats are turned on, and on the overlay: they cost a little every second.
private let statsWarning = "Showing stats can affect game performance."

/// A size on the phone, or SovEmu.Android TV's for the same thing on a TV: Android lays a TV out
/// 1280 dp wide, so one of its dp is 1.5 of the TV's 1920 points.
private func sized(_ phone: CGFloat, tv androidDp: CGFloat) -> CGFloat { onTV(phone, tv: androidDp * 1.5) }

/// The same size on both: Android's phone and TV values are one, in dp.
private func sized(_ value: CGFloat) -> CGFloat { sized(value, tv: value) }

/// Anything that is one thing on the phone and another on a TV.
private func platform<T>(_ phone: T, tv: T) -> T {
    #if os(tvOS)
    tv
    #else
    phone
    #endif
}

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
    /// On a TV, the focused cheat's delete button has the focus rather than its row.
    @State private var cheatSide = false
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
    /// The whole frame, stretched to the console's shape (the box it is in): never cropped.
    @State private var video = SampleBufferVideoView(frame: .zero)

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
            #if os(iOS)
            if showTouch && !menuOpen && session != nil && error == nil { TouchControls(controller: controller) }
            #endif
            if let statsRows {
                StatsOverlay(rows: statsRows, history: history)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(sized(16, tv: 12))
                    .allowsHitTesting(false)
            }
            VStack {
                // A TV opens the menu from the remote (Back or Play/Pause) or a controller's Home.
                #if os(iOS)
                HStack {
                    Spacer()
                    Button { menuOpen = true } label: {
                        Image(systemName: "line.3.horizontal").font(.title2).padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .foregroundStyle(.white)
                }
                #endif
                Spacer()
                if let toast {
                    Text(toast).font(.system(size: sized(17, tv: 16))).foregroundStyle(.white)
                        .padding(.horizontal, sized(16)).padding(.vertical, sized(8))
                        .background(.black.opacity(0.8), in: Capsule()).padding(.bottom, sized(24))
                }
            }
            .padding(onTV(16, tv: 0))
            // Sovereign's player message chip (a glyph before the line, gray-950 at 75% under a
            // 2 pt white/40 edge, two lines at most), but at the very top edge of the screen
            // rather than 12% down, so it stays out of the game.
            if let quality {
                VStack {
                    HStack(spacing: sized(8)) {
                        if let symbol = Self.qualitySymbols[quality.icon] { Image(systemName: symbol) }
                        Text(quality.line).lineLimit(2)
                    }
                    .font(platform(.body, tv: .system(size: 24))).foregroundStyle(.white)
                    .padding(.horizontal, sized(16)).padding(.vertical, sized(8))
                    .frame(minHeight: sized(40))
                    .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255).opacity(0.75), in: RoundedRectangle(cornerRadius: sized(20)))
                    .overlay(RoundedRectangle(cornerRadius: sized(20)).strokeBorder(.white.opacity(0.4), lineWidth: sized(2)))
                    .frame(maxWidth: sized(560))
                    Spacer()
                }
                .padding(.top, sized(8)).padding(.horizontal, sized(16))
                .allowsHitTesting(false)
            }
            if menuOpen { menu }
        }
        .playerChrome()
        #if os(tvOS)
        // The remote, through tvOS's commands (GameController does not see it on an Apple TV):
        // Back or Play/Pause opens the menu; in the menu the click pad moves, a click chooses and
        // Back goes back. A controller raises the same commands, but it plays the game and
        // drives the menu by polling, so its commands are dropped here.
        .onExitCommand { remote(.back) }
        .onPlayPauseCommand { remote(menuOpen ? .confirm : .back) }
        .onMoveCommand { direction in
            switch direction {
            case .up: remote(.up)
            case .down: remote(.down)
            case .left: remote(.left)
            case .right: remote(.right)
            @unknown default: break
            }
        }
        .onTapGesture { remote(.confirm) }
        #endif
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
            cheatSide = false
            Task { await loadPage(page) }
        }
        .onChange(of: gameMenu?.focus) { _, _ in cheatSide = false }
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
                #if os(tvOS)
                tvMenu(gameMenu, items)
                #else
                GameMenuView(
                    title: pageTitle, heading: gameMenu.heading, items: items,
                    focus: Binding(get: { gameMenu.focus }, set: { gameMenu.focus = $0 }),
                    diagrams: gameMenu.diagrams(items),
                    prompt: gameMenu.capturePrompt, onCancelCapture: gameMenu.cancelCapture)
                    .padding()
                #endif
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

    #if os(tvOS)
    /// The menu as SovEmu.Android's TV app draws it: its own panel for each kind of page.
    @ViewBuilder private func tvMenu(_ gameMenu: GameMenu, _ items: [MenuItem]) -> some View {
        switch gameMenu.page {
        case .controllers:
            TVControllerList(devices: gameMenu.devices, items: items, focus: gameMenu.focus)
        case .device:
            TVDevicePage(menu: gameMenu, items: items)
        case .main:
            let style: TVMenuStyle = switch menuPage {
            case .main: .main
            case .save, .load: .slots
            case .disc: .disc
            case .cheats: .cheats
            }
            TVGameMenu(title: pageTitle, system: system, style: style, items: items, focus: gameMenu.focus,
                       note: tvNote, deleteFocused: cheatSide)
        }
    }

    /// What a page says where its rows would be: loading, or nothing there yet.
    private var tvNote: String? {
        switch menuPage {
        case .save, .load: slots == nil ? "Loading saves…" : nil
        case .cheats: cheats == nil ? "Loading cheats…" : cheats?.isEmpty == true ? "No cheats for this game yet. Add one below." : nil
        default: nil
        }
    }
    #endif

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
    #if os(tvOS)
    /// An action from the remote: in play, Back opens the menu; in the menu, every action is the
    /// menu's.
    private func remote(_ action: MenuAction) {
        guard !Controller.padActive() else { return }
        if !menuOpen {
            // A controller's B that closed the menu also raises Back: that copy must not reopen it.
            if action == .back, gameMenu?.isEcho(.back, polled: false) != true { menuOpen = true }
            return
        }
        gameMenu?.act(action, main: pageItems, close: close)
    }
    #endif

    private var pageItems: [MenuItem] {
        switch menuPage {
        case .main: return mainItems
        case .save, .load:
            // A TV says it is loading above the rows, as SovEmu.Android's (and has no Back row:
            // the remote's Back, or B, goes back).
            #if os(tvOS)
            let back: [MenuItem] = []
            guard let slots else { return [] }
            #else
            let back = [MenuItem(id: "back", title: "Back", action: { menuPage = .main })]
            guard let slots else { return [MenuItem(id: "loading", title: "Loading saves…", action: {}, enabled: false)] }
            #endif
            let saving = menuPage == .save
            let now = Int64(Date().timeIntervalSince1970)
            let rows = slotRows(slots, saving ? saveSlots : [autoSlot] + saveSlots, emptyEnabled: saving)
            return rows.map { row in
                MenuItem(
                    id: "slot\(row.slot)", title: row.label,
                    detail: row.save.map { "Saved " + formatAgo(Int64($0.savedAt), now: now) } ?? "Empty",
                    action: { saving ? save(to: row.slot) : load(from: row.slot) },
                    image: row.save?.screenshotUrl ?? "", enabled: row.enabled)
            } + back
        case .disc:
            #if os(tvOS)
            let back: [MenuItem] = []
            #else
            let back = [MenuItem(id: "back", title: "Back", action: { menuPage = .main })]
            #endif
            return (1...max(1, discs)).map { n in
                MenuItem(id: "disc\(n)", title: n == currentDisc ? "Disc \(n) · in the console" : "Disc \(n)",
                         action: { change(disc: n) }, icon: "opticaldisc")
            } + back
        case .cheats:
            #if os(tvOS)
            return tvCheatItems
            #else
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
            #endif
        }
    }

    #if os(tvOS)
    /// The cheats on a TV, as SovEmu.Android's page: each turns on or off with a click, and right
    /// moves to its delete button (left back); then adding one. Loading and an empty list are
    /// said above the rows (`tvNote`).
    private var tvCheatItems: [MenuItem] {
        guard let cheats else { return [] }
        let rows = cheats.map { cheat in
            MenuItem(
                id: "cheat\(cheat.id)", title: cheat.description.isEmpty ? cheat.code : cheat.description,
                detail: cheat.description.isEmpty ? nil : cheat.code,
                action: { cheatSide ? delete(cheat) : toggle(cheat) },
                adjust: { cheatSide = $0 > 0 },
                isOn: cheat.enabled)
        }
        return rows + [MenuItem(id: "add", title: "Add cheat") {
            cheatCode = ""
            cheatName = ""
            addingCheat = true
        }]
    }
    #endif

    private var mainItems: [MenuItem] {
        // The icons are SovEmu.Android's (Lucide's Play, Check, History, Disc3, Sparkles, Gamepad2,
        // Activity, LogOut), which the TV draws.
        var rows = [
            MenuItem(id: "resume", title: "Resume", action: { close() }, icon: "play"),
            MenuItem(id: "save", title: "Save state", action: { menuPage = .save }, icon: "checkmark"),
            MenuItem(id: "load", title: "Load state", action: { menuPage = .load }, icon: "clock.arrow.circlepath"),
        ]
        if discs > 1 {
            #if os(tvOS)
            rows.append(MenuItem(id: "disc", title: "Change disc · disc \(currentDisc) of \(discs)",
                                 action: { menuPage = .disc }, icon: "opticaldisc"))
            #else
            rows.append(MenuItem(id: "disc", title: "Change disc", detail: "Disc \(currentDisc) of \(discs)",
                                 action: { menuPage = .disc }, icon: "opticaldisc"))
            #endif
        }
        rows += [
            MenuItem(id: "cheats", title: "Cheats", action: { menuPage = .cheats }, icon: "sparkles"),
            MenuItem(id: "controllers", title: "Controllers", detail: platform("Players and buttons", tv: nil),
                     action: { gameMenu?.showControllers() }, icon: "gamecontroller"),
            MenuItem(id: "stats", title: settings.stats ? "Hide stats" : "Show stats", detail: statsWarning,
                     action: { settings.stats.toggle() }, icon: "waveform.path.ecg"),
        ]
        // A TV has no touch controls to show.
        #if os(iOS)
        rows.append(MenuItem(id: "touch", title: showTouch ? "Hide touch controls" : "Show touch controls") {
            showTouch.toggle()
            close()
        })
        #endif
        rows.append(MenuItem(id: "quit", title: "Quit game", action: { onExit() }, icon: "rectangle.portrait.and.arrow.right"))
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
                HStack(spacing: sized(8)) {
                    #if os(tvOS)
                    Button("Continue") { chooser.choose(.continue) }.buttonStyle(TVMenuButtonStyle(symbol: "play.fill"))
                    Button("Start over") { chooser.choose(.new) }
                        .buttonStyle(TVMenuButtonStyle(variant: .outline, symbol: "arrow.counterclockwise"))
                    #else
                    Button { chooser.choose(.continue) } label: { Label("Continue", systemImage: "play.fill") }.buttonStyle(.sov())
                    Button { chooser.choose(.new) } label: { Label("Start over", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.sov(.outline))
                    #endif
                }
                .padding(24)
            } else {
                progress.padding(.horizontal, 24)
            }
            // A TV keeps to its safe area, about 5% in from each edge, as Android TV's; a phone a
            // margin.
            Group {
                if let network {
                    Text(network).font(.system(size: sized(14), weight: .semibold)).foregroundStyle(Sov.slate100)
                        .padding(.horizontal, sized(16)).padding(.vertical, sized(6))
                        .background(.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: sized(1)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                HStack(alignment: .bottom, spacing: sized(24)) {
                    VStack(alignment: .leading, spacing: sized(8)) {
                        #if os(tvOS)
                        TVMenuBadge(short: system.short, colour: system.accent, large: true)
                        #else
                        SystemBadge(short: system.short, colour: system.accent)
                        #endif
                        Text(game.title).font(.system(size: sized(32), weight: .black)).foregroundStyle(.white).lineLimit(1)
                        if !status.isEmpty {
                            Text(status).font(.system(size: sized(14))).monospacedDigit().foregroundStyle(Sov.slate300)
                        }
                    }
                    Spacer(minLength: 0)
                    if failed {
                        Image(systemName: "exclamationmark.circle").font(.system(size: sized(36, tv: 40))).foregroundStyle(Sov.red300)
                    } else {
                        ProgressView().controlSize(.large).tint(.white.opacity(0.8))
                            .frame(width: sized(36, tv: 40), height: sized(36, tv: 40))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.horizontal, platform(24, tv: 96)).padding(.vertical, platform(24, tv: 54))
        }
        .ignoresSafeArea()
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
        VStack(spacing: sized(12)) {
            if let fraction = screen.fraction {
                #if os(tvOS)
                // Android's bar: 6 dp on a faint track (tvOS's linear style is a thin line).
                GeometryReader { bar in
                    Capsule().fill(.white.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Sov.accent).frame(width: bar.size.width * min(1, max(0, fraction)))
                        }
                }
                .frame(width: sized(400), height: sized(6))
                .animation(.easeOut(duration: 0.25), value: fraction)
                #else
                ProgressView(value: fraction).progressViewStyle(.linear).tint(Sov.accent).frame(maxWidth: 400)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                #endif
            }
            Text(screen.label).font(.system(size: sized(20), weight: .semibold))
                .foregroundStyle(failed ? Sov.red300 : Sov.slate100).multilineTextAlignment(.center)
            if !screen.detail.isEmpty {
                Text(screen.detail).font(.system(size: sized(16))).monospacedDigit().foregroundStyle(Sov.slate300)
                    .multilineTextAlignment(.center)
            }
            Text(loadingHint).font(.system(size: sized(13))).foregroundStyle(Sov.slate400)
        }
        .frame(maxWidth: sized(560, tv: 560))
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
        VStack(alignment: .leading, spacing: sized(8, tv: 6)) {
            HStack(alignment: .top, spacing: sized(20, tv: 14)) {
                column(Array(rows.prefix(half)))
                column(Array(rows.dropFirst(half)))
            }
            LatencyGraph(history: history).frame(height: sized(64, tv: 48))
            Text(statsWarning).font(.system(size: sized(10, tv: 9))).foregroundStyle(Sov.slate400)
        }
        .padding(.horizontal, sized(12, tv: 8)).padding(.vertical, sized(8, tv: 6))
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: sized(8)))
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The colour of each graphed value's line, by its row's label.
    private static let graphKey = ["Measured button→frame": Sov.accent, "Estimated button→pixel": Sov.slate400]

    private func column(_ rows: [(label: String, value: String)]) -> some View {
        HStack(alignment: .top, spacing: sized(12, tv: 8)) {
            VStack(alignment: .leading, spacing: sized(1, tv: 2)) { ForEach(rows, id: \.label) { Text($0.label).foregroundStyle(Sov.slate400) } }
            VStack(alignment: .trailing, spacing: sized(1, tv: 2)) {
                ForEach(rows, id: \.label) { row in
                    // The graph's key: a jewel in its line's colour beside each value it draws.
                    HStack(spacing: sized(4)) {
                        if let colour = Self.graphKey[row.label] {
                            Circle().fill(colour).frame(width: sized(6), height: sized(6))
                        }
                        Text(row.value).foregroundStyle(.white)
                    }
                }
            }
        }
        .font(.system(size: sized(12, tv: 10), design: .monospaced))
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
            let latest = history.latestMeasured.map { Text("\(Int($0.rounded())) ms").font(.system(size: sized(10), weight: .semibold, design: .monospaced))
                .foregroundStyle(Sov.accent) }
            let latestWidth: CGFloat = latest == nil ? 0 : sized(44)
            let right = size.width - latestWidth - 4
            func y(_ ms: Double) -> CGFloat { size.height * (1 - ms / top) }
            for ms in [top, top / 2] {
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(ms))); $0.addLine(to: CGPoint(x: right, y: y(ms))) },
                               with: .color(Sov.edge), lineWidth: sized(1))
                context.draw(Text("\(Int(ms.rounded()))").font(.system(size: sized(9), design: .monospaced)).foregroundStyle(Sov.slate500),
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
            context.stroke(trace(history.estimated), with: .color(Sov.slate400), lineWidth: sized(1))
            context.stroke(trace(history.measured), with: .color(Sov.accent), lineWidth: sized(2))
            if let latest, let v = history.latestMeasured {
                context.draw(latest, at: CGPoint(x: size.width, y: min(max(y(v), 6), size.height - 6)), anchor: .trailing)
            }
        }
    }
}

#if os(iOS)
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
#endif
