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
}

/// The in-game menu's pages and the controller-driven navigation through them: the D-pad (or
/// left stick, or arrow keys) moves, south (or Enter, Space) confirms, east (or Escape) goes
/// back. The Controllers page lists the connected devices with their players; a device's page
/// changes its player and rebinds each RetroPad button by pressing an input on that device.
/// Mappings are saved to the server (`saveControllerMapping`); players are not saved.
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
        let started = Date()

        var cancelInput: String { identity.isKeyboard ? KeyNames.menu : PadInput.east.rawValue }
    }

    static let captureTimeout: TimeInterval = 8
    static let holdToBind: TimeInterval = 1

    /// The order buttons are listed in for remapping.
    static let buttons: [RetroButton] = [.b, .a, .y, .x, .l, .r, .l2, .r2, .l3, .r3, .select, .start, .up, .down, .left, .right]

    private(set) var page: Page = .main
    var focus = 0
    private(set) var capture: Capture?
    private(set) var devices: [Controller.Device] = []
    /// Bumped when a mapping changes, so its page redraws.
    private var revision = 0
    private(set) var closedAt = Date.distantPast

    @ObservationIgnored let controller: Controller
    @ObservationIgnored var api: SovEmuAPI?
    @ObservationIgnored var flash: (String) -> Void = { _ in }
    @ObservationIgnored private var watchers: [Controller.DeviceKey: PressWatcher] = [:]
    /// New presses on the device being captured (polled every frame, so not observed).
    @ObservationIgnored private var captureWatcher = PressWatcher()
    /// When the capture's cancel input (east, or Escape on a keyboard) went down: a tap
    /// cancels, holding it binds it.
    @ObservationIgnored private var cancelDown: Date?

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
            let mapping = controller.mapping(for: identity.id)
            let family: ControllerFamily? = identity.isKeyboard ? nil : identity.family
            var rows = [
                MenuItem(
                    id: "player", title: "Player \(device.port + 1)", detail: "◀ ▶ to change",
                    action: { [weak self] in self?.move(device, by: device.port == WireProtocol.maxPorts - 1 ? -device.port : 1) },
                    adjust: { [weak self] delta in self?.move(device, by: delta) })
            ]
            for button in Self.buttons {
                let inputs = mapping.inputs(for: button).map { inputLabel($0, family: family) }
                rows.append(MenuItem(
                    id: button.name, title: Self.title(button),
                    detail: inputs.isEmpty ? "—" : inputs.joined(separator: ", "),
                    action: { [weak self] in self?.startCapture(device, button) }))
            }
            // Only the user's own mapping can be reset; a default is already in force.
            if controller.source(for: identity.id) == .user {
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
                let source = controller.source(for: device.identity.id) == .user ? "Yours" : "Default"
                return "\(device.identity.name) (\(device.identity.id)) · \(source)"
            }
        }
    }

    /// What the capture overlay says.
    var capturePrompt: String? {
        guard let capture else { return nil }
        let device = capture.identity.isKeyboard ? "the keyboard" : capture.identity.name
        let cancel = capture.identity.isKeyboard ? "Esc" : capture.identity.family.label(.east)
        return "Press an input on \(device) for \(Self.title(capture.button)).\n"
            + "Tap \(cancel) to cancel, or hold it to bind \(cancel)."
    }

    static func title(_ button: RetroButton) -> String {
        switch button {
        case .select: "Select"
        case .start: "Start"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        default: button.name
        }
    }

    // MARK: Actions

    private func move(_ device: Controller.Device, by delta: Int) {
        let port = (device.port + delta + WireProtocol.maxPorts) % WireProtocol.maxPorts
        controller.setPort(device.key, port)
        devices = controller.devices()
    }

    func startCapture(_ device: Controller.Device, _ button: RetroButton) {
        let held = controller.held()[device.key] ?? []
        captureWatcher = PressWatcher(holding: held)
        cancelDown = nil
        capture = Capture(device: device.key, identity: device.identity, button: button)
    }

    func cancelCapture() {
        capture = nil
        watchers = [:]
    }

    private func bind(_ input: String, _ capture: Capture) {
        let id = capture.identity.id
        let mapping = controller.mapping(for: id).rebinding(input, to: capture.button)
        controller.setUser(id, mapping)
        cancelCapture()
        revision += 1
        guard let api else { return }
        let name = capture.identity.name
        Task { @MainActor in
            do {
                let saved = try await api.saveControllerMapping(controller: id, name: name, bindings: mapping.bindingInputs)
                self.controller.record(saved)
                self.revision += 1
            } catch {
                self.flash("Not saved: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the user's own mapping, then uses what the server says is in force: its default
    /// for the model if it has one, else the built-in defaults.
    private func reset(_ identity: ControllerIdentity) {
        guard let api else { return }
        Task { @MainActor in
            do {
                self.controller.setMappings(try await MappingStore.reset(identity.id, with: api))
                self.revision += 1
                self.flash("\(identity.name): back to the defaults")
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
        case .confirm: rows[focus].action()
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
        if !capture.identity.isKeyboard {
            let keys = all[.keyboard] ?? []
            var keyboard = watchers[.keyboard] ?? PressWatcher(holding: keys)
            let escape = keyboard.pressed(keys).contains(KeyNames.menu)
            watchers[.keyboard] = keyboard
            if escape || held.contains("home") {
                cancelCapture()
                return
            }
        }
        if Date().timeIntervalSince(capture.started) > Self.captureTimeout && cancelDown == nil {
            cancelCapture()
            return
        }
        var pressed = captureWatcher.pressed(held)
        let cancel = capture.cancelInput
        if pressed.remove(cancel) != nil { cancelDown = Date() }
        if let down = cancelDown {
            if !held.contains(cancel) {
                cancelCapture()
                return
            }
            if Date().timeIntervalSince(down) >= Self.holdToBind {
                bind(cancel, capture)
                return
            }
        }
        let bindable = pressed.filter { input in
            capture.identity.isKeyboard ? KeyNames.bindable(input) : PadInput(rawValue: input) != nil
        }
        if let input = bindable.sorted().first {
            bind(input, capture)
        }
    }
}

/// The menu's panel: a list of rows, the focused one highlighted and kept in view.
struct GameMenuView: View {
    let title: String
    let heading: String?
    let items: [MenuItem]
    @Binding var focus: Int
    let prompt: String?
    let onCancelCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).padding(8)
            if let heading {
                Text(heading).font(.headline).foregroundStyle(.white).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, focused: index == focus)
                                .id(item.id)
                                .onTapGesture {
                                    focus = index
                                    item.action()
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
        .frame(width: 380)
        .frame(maxHeight: 520)
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
        HStack {
            if item.adjust != nil && focused { Image(systemName: "chevron.left").font(.caption) }
            Text(item.title).font(.title3)
            Spacer()
            if let detail = item.detail { Text(detail).font(.body).foregroundStyle(.secondary) }
            if item.adjust != nil && focused { Image(systemName: "chevron.right").font(.caption) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(focused ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}
