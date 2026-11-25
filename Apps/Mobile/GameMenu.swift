import Foundation
import SovEmuKit
import SwiftUI

/// One row of the in-game menu.
struct MenuItem: Identifiable {
    let id: String
    let title: String
    var detail: String?
    /// Confirm (south, Enter, Space, or a tap).
    var action: () -> Void
    /// Left (−1) and right (+1), for rows that hold a value.
    var adjust: ((Int) -> Void)?
    /// A picture before the title: a save's screenshot (a `/media/…` path).
    var image: String?
    /// Whether it can be picked (a load picker's empty slot cannot); dimmed when not.
    var enabled = true
    /// A delete button beside the row (a cheat's).
    var onDelete: (() -> Void)?
}

/// The in-game menu's pages and the controller-driven navigation through them: the D-pad (or
/// left stick, or arrow keys) moves, south (or Enter, Space) confirms, east (or Escape) goes
/// back. The Controllers page lists the connected devices with their players; a device's page
/// changes its player, chooses the scope (this system, or all systems) and rebinds each of the
/// system's buttons, by its own label, by pressing an input on that device, with the system's
/// pad and the player's controller drawn side by side. Mappings are saved to the server
/// (`saveControllerMapping`, with `system` for this system); players are not saved.
@Observable
final class GameMenu {
    enum Page: Equatable {
        case main, controllers
        case device(Controller.DeviceKey)
    }

    /// Waiting for an input on `device` to bind to `button`.
    struct Capture {
        let device: Controller.DeviceKey
        let identity: ControllerIdentity
        let button: RetroButton
        /// The button as the row names it ("C").
        let label: String

    }


    /// What the device page draws above its rows.
    struct Diagrams {
        let system: PadLayout?
        /// Nil for a keyboard, which shows key names instead.
        let controller: PadLayout?
        let highlight: DiagramHighlight
    }

    private(set) var page: Page = .main
    var focus = 0
    private(set) var capture: Capture?
    private(set) var devices: [Controller.Device] = []
    /// Bumped when a mapping changes, so its page redraws.
    private var revision = 0
    private(set) var closedAt = Date.distantPast

    /// Which mappings the device page edits: this system's (the default) or every system's.
    private(set) var scope: MappingScope = .everySystem

    @ObservationIgnored let controller: Controller
    /// The system being played: its id and short name.
    @ObservationIgnored var system: (id: String, short: String) = ("", "") {
        didSet { scope = .system(system.id) }
    }
    /// Its buttons and pad, and the controllers' diagrams (nil until they load, or if not).
    @ObservationIgnored var info: ControlsInfo?
    @ObservationIgnored var api: SovEmuAPI?
    @ObservationIgnored var flash: (String) -> Void = { _ in }
    @ObservationIgnored private var watchers: [Controller.DeviceKey: PressWatcher] = [:]
    /// The wait for an input to bind, with its timing (SovEmuKit's `RebindCapture`, as Android's).
    @ObservationIgnored private var rebind: RebindCapture?
    /// Milliseconds on a monotonic clock, for `rebind`.
    @ObservationIgnored var nowMs: () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    init(controller: Controller) {
        self.controller = controller
    }

    /// The menu opened: start on the main page, ignoring whatever is held.
    func open() {
        page = .main
        focus = 0
        capture = nil
        watchers = [:]
        devices = controller.devices()
    }

    func markClosed() { closedAt = Date() }

    func showControllers() {
        devices = controller.devices()
        show(.controllers)
    }

    private func show(_ next: Page) {
        page = next
        focus = 0
    }

    // MARK: Pages

    /// The rows of the current page; `main` is the main page's.
    func items(main: [MenuItem], close: @escaping () -> Void) -> [MenuItem] {
        _ = revision
        switch page {
        case .main:
            return main
        case .controllers:
            var rows = devices.map { device in
                MenuItem(
                    id: "\(device.key)", title: device.identity.name,
                    detail: device.identity.isKeyboard
                        ? "Player \(device.port + 1)"
                        : "\(device.identity.family.displayName) · Player \(device.port + 1)",
                    action: { [weak self] in self?.show(.device(device.key)) },
                    adjust: { [weak self] delta in self?.move(device, by: delta) })
            }
            rows.append(MenuItem(id: "back", title: "Back", action: { [weak self] in self?.show(.main) }))
            return rows
        case .device(let key):
            guard let device = devices.first(where: { $0.key == key }) else { return [] }
            let identity = device.identity
            let mappings = controller.mappings
            let mapping = mappings.mapping(for: identity.id, in: scope)
            let family: ControllerFamily? = identity.isKeyboard ? nil : identity.family
            var rows = [
                MenuItem(
                    id: "scope", title: "Mapping for", detail: scopeName(scope),
                    action: { [weak self] in self?.toggleScope() },
                    adjust: { [weak self] _ in self?.toggleScope() }),
                MenuItem(
                    id: "player", title: "Player \(device.port + 1)", detail: "◀ ▶ to change",
                    action: { [weak self] in self?.move(device, by: device.port == WireProtocol.maxPorts - 1 ? -device.port : 1) },
                    adjust: { [weak self] delta in self?.move(device, by: delta) }),
            ]
            // The system's buttons by its labels ("C" on a Mega Drive is RetroPad A); for every
            // system, all sixteen by RetroPad name.
            for entry in remapButtons(info?.controls, scope: scope) {
                guard let button = entry.retroButton else { continue }
                let inputs = mapping.inputs(for: button).map { inputLabel($0, family: family) }
                rows.append(MenuItem(
                    id: button.name, title: entry.label,
                    detail: "←  " + (inputs.isEmpty ? "—" : inputs.joined(separator: ", ")),
                    action: { [weak self] in self?.startCapture(device, button, label: entry.label) }))
            }
            // The system's analog controls: always their own stick, so shown but never rebound.
            if !identity.isKeyboard {
                for stick in remapSticks(info?.controls, scope: scope) {
                    rows.append(MenuItem(
                        id: "stick:" + stick.key, title: stick.label, detail: "←  " + stick.stickName,
                        action: { [weak self] in
                            self?.flash("\(stick.label) is always the \(stick.stickName.lowercased()): sticks are not remapped")
                        }))
                }
            }
            // Only the user's own mapping in this scope can be reset; a default is in force.
            if mappings.canReset(identity.id, in: scope) {
                rows.append(MenuItem(id: "reset", title: "Reset to defaults", action: { [weak self] in self?.reset(identity) }))
            }
            rows.append(MenuItem(id: "back", title: "Back", action: { [weak self] in self?.show(.controllers) }))
            return rows
        }
    }

    var heading: String? {
        switch page {
        case .main: nil
        case .controllers: devices.isEmpty ? "No controller or keyboard connected. The touch controls are player 1." : "Controllers"
        case .device(let key):
            devices.first { $0.key == key }.map { device in
                let origin = controller.mappings.origin(for: device.identity.id, in: scope)
                return "\(device.identity.name) · \(origin.text)"
            }
        }
    }

    /// What the capture overlay says (docs/CONTROLLERS.md, Remapping).
    var capturePrompt: String? {
        guard let capture else { return nil }
        let what = capture.identity.isKeyboard ? "Press a key" : "Press a button on \(capture.identity.name)"
        let back = capture.identity.isKeyboard ? "Esc" : capture.identity.family.label(.east)
        return "\(what) for \(capture.label)\n· tap \(back) to cancel, hold it to bind it"
    }

    func scopeName(_ scope: MappingScope) -> String {
        scope == .everySystem ? "All systems" : "This system (\(system.short))"
    }

    /// The diagrams for the device page, lighting the focused button's keys.
    func diagrams(_ rows: [MenuItem]) -> Diagrams? {
        guard case .device(let key) = page, let device = devices.first(where: { $0.key == key }) else { return nil }
        let focused = rows.indices.contains(focus) ? RetroButton(name: rows[focus].id) : nil
        let button = capture?.button ?? focused
        let mapping = controller.mappings.mapping(for: device.identity.id, in: scope)
        let systemLayout = scope == .everySystem ? nil : info?.controls?.layout
        let controllerLayout = device.identity.isKeyboard ? nil : info?.layout(for: device.identity.family)
        guard systemLayout != nil || controllerLayout != nil else { return nil }
        let stick = capture == nil && rows.indices.contains(focus)
            ? remapSticks(info?.controls, scope: scope).first { "stick:" + $0.key == rows[focus].id } : nil
        let highlight = stick.map { DiagramHighlight(stick: $0) } ?? DiagramHighlight(button: button, mapping: mapping)
        return Diagrams(system: systemLayout, controller: controllerLayout, highlight: highlight)
    }

    // MARK: Actions

    private func move(_ device: Controller.Device, by delta: Int) {
        let port = (device.port + delta + WireProtocol.maxPorts) % WireProtocol.maxPorts
        controller.setPort(device.key, port)
        devices = controller.devices()
    }

    private func toggleScope() {
        scope = scope == .everySystem ? .system(system.id) : .everySystem
    }

    func startCapture(_ device: Controller.Device, _ button: RetroButton, label: String) {
        let held = controller.held()[device.key] ?? []
        let isKeyboard = device.identity.isKeyboard
        rebind = RebindCapture(
            back: RebindCapture.backInput(isKeyboard: isKeyboard), alreadyHeld: held, startMs: nowMs(),
            bindable: { isKeyboard ? KeyNames.bindable($0) : PadInput(rawValue: $0) != nil })
        capture = Capture(device: device.key, identity: device.identity, button: button, label: label)
    }

    func cancelCapture() {
        capture = nil
        watchers = [:]
    }

    private func bind(_ input: String, _ capture: Capture) {
        let id = capture.identity.id
        let scope = scope
        let mappings = controller.mappings
        let mapping = mappings.mapping(for: id, in: scope).rebinding(input, to: capture.button)
        controller.mappings = mappings.applying(mapping, for: id, in: scope)
        cancelCapture()
        revision += 1
        guard let api else { return }
        let name = capture.identity.name
        Task { @MainActor in
            do {
                // Saved in the scope, then both lists read back: what is in force may change.
                self.controller.mappings = try await mappings.saving(mapping, for: id, name: name, in: scope, with: api)
                self.revision += 1
            } catch {
                self.flash("Not saved: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the user's own mapping in the scope, then uses what the server says is in force:
    /// their own for every system, a default for the model, else the built-in defaults.
    private func reset(_ identity: ControllerIdentity) {
        guard let api else { return }
        let scope = scope
        Task { @MainActor in
            do {
                self.controller.mappings = try await self.controller.mappings.resetting(identity.id, in: scope, with: api)
                self.revision += 1
                let origin = self.controller.mappings.origin(for: identity.id, in: scope)
                self.flash("\(identity.name) (\(self.scopeName(scope))): now \(origin.text.lowercased())")
            } catch {
                self.flash("Not reset: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Polling

    /// Reads the devices once (about every frame while the menu is open).
    func poll(main: [MenuItem], close: @escaping () -> Void) {
        let now = controller.devices()
        if now.map(\.key) != devices.map(\.key) || now.map(\.port) != devices.map(\.port) { devices = now }
        if case .device(let key) = page, !devices.contains(where: { $0.key == key }) {
            capture = nil
            show(.controllers)
        }
        if capture != nil {
            pollCapture()
            return
        }
        let rows = items(main: main, close: close)
        let clamped = min(focus, max(0, rows.count - 1))
        if clamped != focus { focus = clamped }
        for (key, held) in controller.held(stick: true) {
            var watcher = watchers[key] ?? PressWatcher(holding: held)
            let pressed = watcher.pressed(held)
            watchers[key] = watcher
            let before = page
            for input in pressed.sorted() {
                guard let action = MenuAction.of(input) else { continue }
                perform(action, rows, close: close)
                // A row may have changed the page or started a capture: read the rest next time.
                if capture != nil || page != before { return }
            }
        }
    }

    private func perform(_ action: MenuAction, _ rows: [MenuItem], close: () -> Void) {
        guard !rows.isEmpty else {
            if action == .back || action == .confirm { back(close) }
            return
        }
        switch action {
        case .up: focus = max(0, focus - 1)
        case .down: focus = min(rows.count - 1, focus + 1)
        case .left: rows[focus].adjust?(-1)
        case .right: rows[focus].adjust?(1)
        case .confirm: if rows[focus].enabled { rows[focus].action() }
        case .back: back(close)
        }
    }

    private func back(_ close: () -> Void) {
        switch page {
        case .main: close()
        case .controllers: show(.main)
        case .device: show(.controllers)
        }
    }

    private func pollCapture() {
        guard let capture else { return }
        let all = controller.held()
        guard let held = all[capture.device] else {
            cancelCapture()
            return
        }
        // Escape on a keyboard, or Home on the pad, always cancels.
        var guide = false
        if !capture.identity.isKeyboard {
            let keys = all[.keyboard] ?? []
            var keyboard = watchers[.keyboard] ?? PressWatcher(holding: keys)
            guide = keyboard.pressed(keys).contains(KeyNames.menu) || held.contains("home")
            watchers[.keyboard] = keyboard
        }
        guard var rebind else { return }
        let outcome = rebind.update(held: held, nowMs: nowMs(), guide: guide)
        self.rebind = rebind
        switch outcome {
        case .waiting: break
        case .bind(let input): bind(input, capture)
        case .cancel: cancelCapture()
        }
    }
}

/// The menu's panel: a list of rows, the focused one highlighted and kept in view.
struct GameMenuView: View {
    let title: String
    let heading: String?
    let items: [MenuItem]
    @Binding var focus: Int
    var diagrams: GameMenu.Diagrams?
    let prompt: String?
    let onCancelCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).padding(8)
            if let heading {
                Text(heading).font(.headline).foregroundStyle(.white).padding(.horizontal, 12).padding(.bottom, 4)
            }
            if let diagrams {
                DiagramPair(diagrams: diagrams).frame(maxWidth: .infinity).padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, focused: index == focus)
                                .id(item.id)
                                .onTapGesture {
                                    focus = index
                                    if item.enabled { item.action() }
                                }
                        }
                    }
                }
                .onChange(of: focus) { _, new in
                    if items.indices.contains(new) { withAnimation { proxy.scrollTo(items[new].id, anchor: .center) } }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: diagrams == nil ? 380 : 460)
        .frame(maxHeight: diagrams == nil ? 520 : 640)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 0.082, green: 0.098, blue: 0.133), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if let prompt {
                VStack(spacing: 16) {
                    Text(prompt).multilineTextAlignment(.center).foregroundStyle(.white)
                    Button("Cancel", action: onCancelCapture).buttonStyle(.bordered)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func row(_ item: MenuItem, focused: Bool) -> some View {
        HStack(spacing: 12) {
            if item.adjust != nil && focused { Image(systemName: "chevron.left").font(.caption) }
            if let image = item.image {
                ZStack {
                    Color.black
                    if !image.isEmpty { RemoteImage(path: image, contentMode: .fit, pixelated: true) }
                }
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
            }
            if item.image != nil, let detail = item.detail {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.title3)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Text(item.title).font(.title3)
                Spacer()
                if let detail = item.detail { Text(detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
            }
            if item.adjust != nil && focused { Image(systemName: "chevron.right").font(.caption) }
            if let onDelete = item.onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.callout).foregroundStyle(Sov.slate400).frame(width: 36, height: 36)
                        .background(.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(item.enabled ? 1 : 0.4)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(focused ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}
