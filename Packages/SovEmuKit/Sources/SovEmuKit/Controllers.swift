import Foundation

// Controllers as `docs/CONTROLLERS.md` (in SovEmu) describes them, shared with the web and
// Android clients: which model a controller is (its ID, the key for the user's saved mapping),
// its family (for button labels), the positional input names, keyboard key names, the default
// mappings, hotkeys and players. Plain Swift with no GameController types, so `swift test`
// covers it; the app feeds it what GameController reports.

/// A controller's inputs by position: the W3C standard gamepad's buttons 0-15, in order.
public enum PadInput: String, CaseIterable, Sendable {
    case south, east, west, north, l1, r1, l2, r2, select, start, l3, r3, up, down, left, right
}

/// Which labels a controller's buttons carry.
public enum ControllerFamily: String, Sendable, CaseIterable {
    case xbox, playstation, nintendo, generic

    public var displayName: String {
        switch self {
        case .xbox: "Xbox"
        case .playstation: "PlayStation"
        case .nintendo: "Nintendo"
        case .generic: "Generic"
        }
    }

    /// An input as this family's controllers label it: `south` is A, ✕ or B.
    public func label(_ input: PadInput) -> String {
        switch (self, input) {
        case (_, .up): "D-pad ↑"
        case (_, .down): "D-pad ↓"
        case (_, .left): "D-pad ←"
        case (_, .right): "D-pad →"
        case (.playstation, .south): "✕"
        case (.playstation, .east): "○"
        case (.playstation, .west): "□"
        case (.playstation, .north): "△"
        case (.playstation, .l1): "L1"
        case (.playstation, .r1): "R1"
        case (.playstation, .l2): "L2"
        case (.playstation, .r2): "R2"
        case (.playstation, .select): "Create"
        case (.playstation, .start): "Options"
        case (.playstation, .l3): "L3"
        case (.playstation, .r3): "R3"
        case (.nintendo, .south): "B"
        case (.nintendo, .east): "A"
        case (.nintendo, .west): "Y"
        case (.nintendo, .north): "X"
        case (.nintendo, .l1): "L"
        case (.nintendo, .r1): "R"
        case (.nintendo, .l2): "ZL"
        case (.nintendo, .r2): "ZR"
        case (.nintendo, .select): "−"
        case (.nintendo, .start): "+"
        case (_, .south): "A"
        case (_, .east): "B"
        case (_, .west): "X"
        case (_, .north): "Y"
        case (_, .l1): "LB"
        case (_, .r1): "RB"
        case (_, .l2): "LT"
        case (_, .r2): "RT"
        case (_, .select): "View"
        case (_, .start): "Menu"
        case (_, .l3): "LS"
        case (_, .r3): "RS"
        }
    }
}

/// Who a controller is: its mapping key, its own name and its family.
public struct ControllerIdentity: Equatable, Sendable {
    /// `keyboard`, a known model (`xbox`, `dualsense` …) or `pad:name:<slug>`.
    public let id: String
    public let name: String
    public let family: ControllerFamily

    public init(id: String, name: String, family: ControllerFamily) {
        self.id = id
        self.name = name
        self.family = family
    }

    public static let keyboardID = "keyboard"
    public static let keyboard = ControllerIdentity(id: keyboardID, name: "Keyboard", family: .generic)

    public var isKeyboard: Bool { id == Self.keyboardID }

    /// The known models by `GCController.productCategory` (docs/CONTROLLERS.md).
    static let models: [String: (id: String, family: ControllerFamily)] = [
        "Xbox One": ("xbox", .xbox),
        "DualSense": ("dualsense", .playstation),
        "DualSense Edge": ("dualsense", .playstation),
        "DualShock 4": ("dualshock4", .playstation),
        "Switch Pro Controller": ("switch-pro", .nintendo),
    ]

    /// A GameController controller, from its `productCategory` and `vendorName`. iOS reports
    /// no vendor or product IDs, so anything but a known model is `pad:name:` of its name.
    public static func identify(productCategory: String, vendorName: String?) -> ControllerIdentity {
        let vendor = vendorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = vendor.isEmpty ? productCategory : vendor
        if let model = models[productCategory] {
            return ControllerIdentity(id: model.id, name: name, family: model.family)
        }
        let id = "pad:name:" + (slug(name).isEmpty ? "unknown" : slug(name))
        return ControllerIdentity(id: id, name: name, family: family(fromName: "\(productCategory) \(vendor)"))
    }

    static func family(fromName name: String) -> ControllerFamily {
        let lower = name.lowercased()
        if lower.contains("xbox") || lower.contains("xinput") { return .xbox }
        if ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5"].contains(where: lower.contains) {
            return .playstation
        }
        if ["nintendo", "switch", "joy-con"].contains(where: lower.contains) { return .nintendo }
        return .generic
    }

    /// A name as an ID part: lowercase ASCII, every run of other characters a `-`, trimmed of
    /// `-`, at most 48 characters.
    public static func slug(_ name: String) -> String {
        var out = ""
        var dash = false
        for scalar in name.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if dash && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                dash = false
            } else {
                dash = true
            }
        }
        return String(String(out.prefix(48)).trimmingSuffix("-"))
    }
}

extension String {
    fileprivate func trimmingSuffix(_ c: Character) -> Substring {
        var s = Substring(self)
        while s.last == c { s = s.dropLast() }
        return s
    }
}

// MARK: - Keyboard

/// Keyboard keys as W3C `KeyboardEvent.code` names. GameController's `GCKeyCode` is the HID
/// keyboard usage (page 0x07), so the app passes `code.rawValue` here.
public enum KeyNames {
    /// The fast-forward and rewind keys: never bound.
    public static let fastForward = "Tab"
    public static let rewind = "Backspace"
    public static let reserved: Set<String> = [fastForward, rewind]
    /// Opens the in-game menu, unless the keyboard's mapping binds it.
    public static let menu = "Escape"

    static let usages: [Int: String] = {
        var names: [Int: String] = [:]
        for (i, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { names[0x04 + i] = "Key\(letter)" }
        for i in 1...9 { names[0x1d + i] = "Digit\(i)" }
        names[0x27] = "Digit0"
        let named: [Int: String] = [
            0x28: "Enter", 0x29: "Escape", 0x2a: "Backspace", 0x2b: "Tab", 0x2c: "Space",
            0x2d: "Minus", 0x2e: "Equal", 0x2f: "BracketLeft", 0x30: "BracketRight", 0x31: "Backslash",
            0x33: "Semicolon", 0x34: "Quote", 0x35: "Backquote", 0x36: "Comma", 0x37: "Period",
            0x38: "Slash", 0x39: "CapsLock",
            0x49: "Insert", 0x4a: "Home", 0x4b: "PageUp", 0x4c: "Delete", 0x4d: "End", 0x4e: "PageDown",
            0x4f: "ArrowRight", 0x50: "ArrowLeft", 0x51: "ArrowDown", 0x52: "ArrowUp",
            0x54: "NumpadDivide", 0x55: "NumpadMultiply", 0x56: "NumpadSubtract", 0x57: "NumpadAdd",
            0x58: "NumpadEnter", 0x63: "NumpadDecimal",
            0xe0: "ControlLeft", 0xe1: "ShiftLeft", 0xe2: "AltLeft", 0xe3: "MetaLeft",
            0xe4: "ControlRight", 0xe5: "ShiftRight", 0xe6: "AltRight", 0xe7: "MetaRight",
        ]
        names.merge(named) { $1 }
        for i in 1...12 { names[0x39 + i] = "F\(i)" }
        for i in 1...9 { names[0x58 + i] = "Numpad\(i)" }
        names[0x62] = "Numpad0"
        return names
    }()

    /// The `KeyboardEvent.code` for a HID keyboard usage (`GCKeyCode.rawValue`), if it has one.
    public static func code(forUsage usage: Int) -> String? { usages[usage] }

    /// Every named key's usage, for polling a keyboard: stored, as it is read on every tick.
    public static let allUsages: [Int] = usages.keys.sorted()

    /// Whether a key may be bound (not a hotkey).
    public static func bindable(_ code: String) -> Bool { !reserved.contains(code) }

    /// A key as a person would name it: `KeyZ` is Z, `ArrowUp` ↑, `ShiftLeft` Left Shift.
    public static func label(_ code: String) -> String {
        let arrows = ["ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→"]
        if let arrow = arrows[code] { return arrow }
        if code.hasPrefix("Key") && code.count == 4 { return String(code.dropFirst(3)) }
        if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
        for modifier in ["Shift", "Control", "Alt", "Meta"] {
            for side in ["Left", "Right"] where code == modifier + side {
                return "\(side) \(modifier == "Alt" ? "Option" : modifier == "Meta" ? "Command" : modifier)"
            }
        }
        return code
    }
}

/// A controller's stick directions, bindable like buttons (docs/CONTROLLERS.md, "Inputs").
public let stickInputNames = ["ls_up", "ls_down", "ls_left", "ls_right", "rs_up", "rs_down", "rs_left", "rs_right"]

/// The stick directions pushed past half-way. Axes are GameController's: y points up.
public func stickInputs(lx: Float, ly: Float, rx: Float, ry: Float, threshold: Float = 0.5) -> Set<String> {
    var out = Set<String>()
    for (side, x, y) in [("ls", lx, ly), ("rs", rx, ry)] {
        if x < -threshold { out.insert("\(side)_left") }
        if x > threshold { out.insert("\(side)_right") }
        if y > threshold { out.insert("\(side)_up") }
        if y < -threshold { out.insert("\(side)_down") }
    }
    return out
}

/// The diagram key an input lights: a stick direction lights its stick.
public func diagramKey(_ input: String) -> String {
    if input.hasPrefix("ls_") { return "l3" }
    if input.hasPrefix("rs_") { return "r3" }
    return input
}

/// An input as its device labels it: a pad input by family (`✕`, `LB`), a stick direction
/// (`LS ←`), else a key's name.
public func inputLabel(_ input: String, family: ControllerFamily?) -> String {
    if let family, let pad = PadInput(rawValue: input) { return family.label(pad) }
    if stickInputNames.contains(input) {
        let parts = input.split(separator: "_")
        let arrows = ["up": "↑", "down": "↓", "left": "←", "right": "→"]
        return "\(parts[0].uppercased()) \(arrows[String(parts[1])] ?? "")"
    }
    return KeyNames.label(input)
}

// MARK: - Mappings

extension RetroButton {
    /// The GraphQL `PadButton` name: `B`, `SELECT`, `L2` …
    public var name: String {
        switch self {
        case .b: "B"
        case .y: "Y"
        case .select: "SELECT"
        case .start: "START"
        case .up: "UP"
        case .down: "DOWN"
        case .left: "LEFT"
        case .right: "RIGHT"
        case .a: "A"
        case .x: "X"
        case .l: "L"
        case .r: "R"
        case .l2: "L2"
        case .r2: "R2"
        case .l3: "L3"
        case .r3: "R3"
        }
    }

    public init?(name: String) {
        guard let button = RetroButton.allCases.first(where: { $0.name == name }) else { return nil }
        self = button
    }
}

/// Input → RetroPad button for one controller model. An input drives one button; a button may
/// have several inputs.
public struct ControllerMap: Equatable, Sendable {
    public var bindings: [String: RetroButton]

    public init(_ bindings: [String: RetroButton] = [:]) {
        self.bindings = bindings
    }

    /// By position, as libretro's SNES-shaped RetroPad expects.
    public static let pad = ControllerMap([
        "south": .b, "east": .a, "west": .y, "north": .x, "l1": .l, "r1": .r, "l2": .l2, "r2": .r2,
        "select": .select, "start": .start, "l3": .l3, "r3": .r3,
        "up": .up, "down": .down, "left": .left, "right": .right,
    ])

    public static let keyboard = ControllerMap([
        "ArrowUp": .up, "ArrowDown": .down, "ArrowLeft": .left, "ArrowRight": .right,
        "KeyZ": .b, "KeyX": .a, "KeyA": .y, "KeyS": .x, "KeyQ": .l, "KeyW": .r,
        "Enter": .start, "ShiftLeft": .select, "ShiftRight": .select,
    ])

    /// The defaults for a controller ID.
    public static func defaults(for controller: String) -> ControllerMap {
        controller == ControllerIdentity.keyboardID ? keyboard : pad
    }

    /// From the API's bindings; unknown button names are skipped.
    public init(bindings: [ControllerBinding]) {
        var map: [String: RetroButton] = [:]
        for binding in bindings {
            if let button = RetroButton(name: binding.button) { map[binding.input] = button }
        }
        self.init(map)
    }

    /// Whether any of the left stick's directions is bound: then it no longer doubles as the D-pad.
    public var bindsLeftStick: Bool { bindings.keys.contains { $0.hasPrefix("ls_") } }

    /// The RetroPad state of a set of pressed inputs.
    public func state(_ pressed: some Sequence<String>) -> UInt16 {
        var state: UInt16 = 0
        for input in pressed {
            if let button = bindings[input] { state |= button.bit }
        }
        return state
    }

    /// The inputs bound to `button`, in a stable order.
    public func inputs(for button: RetroButton) -> [String] {
        let order = Dictionary(uniqueKeysWithValues: PadInput.allCases.enumerated().map { ($1.rawValue, $0) })
        return bindings.filter { $0.value == button }.map(\.key).sorted {
            switch (order[$0], order[$1]) {
            case let (a?, b?): a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0 < $1
            }
        }
    }

    /// Binds `input` to `button`, like a console frontend: the button then has just that input
    /// on this controller, and the input stops driving anything else.
    public func rebinding(_ input: String, to button: RetroButton) -> ControllerMap {
        var next = bindings.filter { $0.value != button && $0.key != input }
        next[input] = button
        return ControllerMap(next)
    }

    /// As the API's binding list, in a stable order.
    public var bindingInputs: [ControllerBinding] {
        bindings.sorted { $0.key < $1.key }.map { ControllerBinding(input: $0.key, button: $0.value.name) }
    }
}

/// The mappings in force for a user, as `controllerMappings` returns them for one system (or
/// for every system): one per model, each with where it comes from. A model the server does
/// not list uses the built-in defaults.
public struct MappingStore: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let map: ControllerMap
        public let source: MappingSource
        /// The system it is for, or nil for every system.
        public let system: String?
    }

    private var entries: [String: Entry]

    public init(_ mappings: [ControllerMapping] = []) {
        entries = Dictionary(
            mappings.map { ($0.controller, Entry(map: ControllerMap(bindings: $0.bindings), source: $0.source, system: $0.system)) }
        ) { $1 }
    }

    /// The mapping in force for a controller model.
    public func mapping(for controller: String) -> ControllerMap {
        entries[controller]?.map ?? .defaults(for: controller)
    }

    /// Where it comes from; nil for the built-in defaults.
    public func entry(for controller: String) -> Entry? { entries[controller] }

    fileprivate mutating func set(_ controller: String, _ entry: Entry) { entries[controller] = entry }
}

/// Which mappings a change applies to: this system's, or every system's.
public enum MappingScope: Equatable, Sendable {
    case system(String)
    case everySystem

    /// The `system` argument for saving and resetting: nil for every system.
    public var systemArgument: String? {
        if case .system(let id) = self { return id }
        return nil
    }
}

/// Where the mapping in force comes from, as the remap screen says it.
public enum MappingOrigin: Equatable, Sendable {
    case yoursForThisSystem, yoursForAllSystems, defaults

    public var text: String {
        switch self {
        case .yoursForThisSystem: "Yours for this system"
        case .yoursForAllSystems: "Yours for all systems"
        case .defaults: "Default"
        }
    }
}

/// A user's mappings while playing one system: those in force there (what the game uses) and
/// those for every system (what "All systems" edits), as the server layers them
/// (docs/CONTROLLERS.md): their own for the system, their own for every system, the default
/// for the system, the default for every system, the built-in defaults.
public struct Mappings: Sendable, Equatable {
    public let system: String
    /// `controllerMappings(system:)`: in force on this system.
    public private(set) var inSystem: MappingStore
    /// `controllerMappings`: in force on every system.
    public private(set) var everySystem: MappingStore

    public init(system: String, inSystem: MappingStore = MappingStore(), everySystem: MappingStore = MappingStore()) {
        self.system = system
        self.inSystem = inSystem
        self.everySystem = everySystem
    }

    /// The mapping in force for a model in play.
    public func mapping(for controller: String) -> ControllerMap { inSystem.mapping(for: controller) }

    /// The mapping a scope shows and edits.
    public func mapping(for controller: String, in scope: MappingScope) -> ControllerMap {
        scope == .everySystem ? everySystem.mapping(for: controller) : inSystem.mapping(for: controller)
    }

    /// Where the mapping a scope shows comes from.
    public func origin(for controller: String, in scope: MappingScope) -> MappingOrigin {
        let entry = scope == .everySystem ? everySystem.entry(for: controller) : inSystem.entry(for: controller)
        guard let entry, entry.source == .user else { return .defaults }
        return entry.system == nil ? .yoursForAllSystems : .yoursForThisSystem
    }

    /// Whether the user has their own mapping in exactly this scope, which a reset removes.
    public func canReset(_ controller: String, in scope: MappingScope) -> Bool {
        switch scope {
        case .everySystem: everySystem.entry(for: controller)?.source == .user
        case .system: origin(for: controller, in: scope) == .yoursForThisSystem
        }
    }

    /// The user's change, applied locally before the server answers, by the same layering.
    public func applying(_ map: ControllerMap, for controller: String, in scope: MappingScope) -> Mappings {
        var next = self
        switch scope {
        case .system(let id):
            next.inSystem.set(controller, .init(map: map, source: .user, system: id))
        case .everySystem:
            next.everySystem.set(controller, .init(map: map, source: .user, system: nil))
            // The user's own for every system beats any default, not their own for this system.
            if origin(for: controller, in: .system(system)) != .yoursForThisSystem {
                next.inSystem.set(controller, .init(map: map, source: .user, system: nil))
            }
        }
        return next
    }

    /// Both lists from the server.
    public static func fetch(system: String, with service: some ControllerMappingService) async throws -> Mappings {
        async let here = service.controllerMappings(system: system)
        async let everywhere = service.controllerMappings(system: nil)
        return Mappings(system: system, inSystem: MappingStore(try await here), everySystem: MappingStore(try await everywhere))
    }

    /// Saves a model's mapping in a scope, then reads both lists again.
    public func saving(
        _ map: ControllerMap, for controller: String, name: String, in scope: MappingScope,
        with service: some ControllerMappingService
    ) async throws -> Mappings {
        _ = try await service.saveControllerMapping(
            controller: controller, system: scope.systemArgument, name: name, bindings: map.bindingInputs)
        return try await Self.fetch(system: system, with: service)
    }

    /// Removes the user's own mapping for a model in a scope, then reads both lists again: the
    /// next layer applies (their own for every system, a server default, else the built-in).
    public func resetting(_ controller: String, in scope: MappingScope, with service: some ControllerMappingService)
        async throws -> Mappings
    {
        _ = try await service.resetControllerMapping(controller: controller, system: scope.systemArgument)
        return try await Self.fetch(system: system, with: service)
    }
}

// MARK: - Diagrams

/// Which keys to light on the two diagrams while a RetroPad button is chosen: the system pad's
/// key for the button, and the controller's keys for every input mapped to it.
public struct DiagramHighlight: Equatable, Sendable {
    public let systemKeys: Set<String>
    public let controllerKeys: Set<String>

    public init(button: RetroButton?, mapping: ControllerMap) {
        guard let button else {
            systemKeys = []
            controllerKeys = []
            return
        }
        systemKeys = [button.name]
        controllerKeys = Set(mapping.inputs(for: button).map(diagramKey).filter { PadInput(rawValue: $0) != nil })
    }

    /// A system's analog control: its key on the system's pad, and its stick on the controller's.
    public init(stick: SystemStick) {
        systemKeys = [stick.key]
        controllerKeys = [stick.controllerKey]
    }
}

/// The analog controls the remap screen lists after the buttons: the system's, in its own scope
/// only. They show their stick and are never rebound.
public func remapSticks(_ controls: SystemControls?, scope: MappingScope) -> [SystemStick] {
    if case .system = scope, let controls { return controls.sticks }
    return []
}

/// The rows the remap screen lists for a scope: the system's buttons with its labels (Mega
/// Drive: `Y` is "A"), or for every system all sixteen by RetroPad name.
public func remapButtons(_ controls: SystemControls?, scope: MappingScope) -> [SystemButton] {
    if case .system = scope, let controls {
        return controls.buttons.filter { $0.retroButton != nil }
    }
    let order: [RetroButton] = [.b, .a, .y, .x, .l, .r, .l2, .r2, .l3, .r3, .select, .start, .up, .down, .left, .right]
    return order.map { SystemButton(button: $0.name, label: $0.displayName) }
}

extension RetroButton {
    /// The RetroPad name as a row shows it: `B`, `Select`, `Up` …
    public var displayName: String {
        switch self {
        case .select: "Select"
        case .start: "Start"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        default: name
        }
    }
}

// MARK: - Hotkeys

/// Hotkeys read from a port's RetroPad state, after mapping.
public struct HotkeyReading: Equatable, Sendable {
    /// The state the game sees: SELECT, L and R are kept from it while a combo is held.
    public var state: UInt16
    public var fastForward: Bool
    public var rewind: Bool
    public var menu: Bool

    /// SELECT+R fast-forwards, SELECT+L rewinds, SELECT+START opens the menu.
    public static func read(_ state: UInt16) -> HotkeyReading {
        let held = { (b: RetroButton) in state & b.bit != 0 }
        let fastForward = held(.select) && held(.r)
        let rewind = held(.select) && held(.l)
        let menu = held(.select) && held(.start)
        var masked = state
        if fastForward || rewind { masked &= ~(RetroButton.select.bit | RetroButton.l.bit | RetroButton.r.bit) }
        if menu { masked &= ~(RetroButton.select.bit | RetroButton.start.bit) }
        return HotkeyReading(state: masked, fastForward: fastForward, rewind: rewind, menu: menu)
    }
}

// MARK: - Players

/// Which player (port 0-3) each controller drives: a new one takes the lowest free port (the
/// last port when all are taken), a gone one frees its port, and a person can move one by hand.
/// Several controllers may share a port. Assignments live for the session only.
public struct Players<Key: Hashable>: Sendable where Key: Sendable {
    private var ports: [Key: Int] = [:]

    public init() {}

    /// The controller's port, assigning the lowest free one the first time it is seen.
    @discardableResult
    public mutating func join(_ key: Key) -> Int {
        if let known = ports[key] { return known }
        let taken = Set(ports.values)
        let port = (0..<WireProtocol.maxPorts).first { !taken.contains($0) } ?? WireProtocol.maxPorts - 1
        ports[key] = port
        return port
    }

    public mutating func leave(_ key: Key) {
        ports[key] = nil
    }

    public func port(_ key: Key) -> Int? { ports[key] }

    /// Moves a controller to a port (clamped to 0-3).
    public mutating func set(_ key: Key, port: Int) {
        ports[key] = max(0, min(WireProtocol.maxPorts - 1, port))
    }
}

// MARK: - Capturing an input

/// New presses on one device, for remapping and menu navigation: an input counts when it goes
/// down, so whatever was already held when watching started is ignored until released.
public struct PressWatcher: Sendable {
    private var held: Set<String>

    public init(holding: Set<String> = []) {
        held = holding
    }

    /// The inputs that went down since the last call.
    public mutating func pressed(_ now: Set<String>) -> Set<String> {
        let new = now.subtracting(held)
        held = now
        return new
    }
}

/// What a press means in a controller-driven menu.
public enum MenuAction: Equatable, Sendable {
    case up, down, left, right, confirm, back
}

extension MenuAction {
    /// The menu action of a newly pressed input on a pad (by position: south confirms, east
    /// goes back) or a keyboard (arrows, Enter or Space, Escape).
    public static func of(_ input: String) -> MenuAction? {
        switch input {
        case "up", "ArrowUp": .up
        case "down", "ArrowDown": .down
        case "left", "ArrowLeft": .left
        case "right", "ArrowRight": .right
        case "south", "Enter", "Space", "NumpadEnter": .confirm
        case "east", "Escape": .back
        default: nil
        }
    }
}

/// Waiting for the input to bind to a button, on one device (docs/CONTROLLERS.md, "Remapping"),
/// as SovEmu.Android's `RebindCapture` and SovEmu.Web's: fed the inputs held and a clock. Any
/// other new input binds at once; the menu Back input (`back`: `east` on a pad, `Escape` on a
/// keyboard) cancels on a quick tap and binds once held for `holdMs`; home/guide cancels;
/// `timeoutMs` without a new input cancels. Inputs held when the wait starts are ignored until
/// released. `bindable` says which inputs may be bound at all (a key the app reserves may not).
public struct RebindCapture: Sendable {
    public enum Outcome: Sendable, Equatable {
        case waiting
        case bind(String)
        case cancel(timedOut: Bool)
    }

    public static let holdMs: Int64 = 1000
    public static let timeoutMs: Int64 = 8000

    private let back: String
    private let bindable: @Sendable (String) -> Bool
    private var ignored: Set<String>
    private var backSince: Int64?
    private var lastInput: Int64

    public init(back: String, alreadyHeld: Set<String>, startMs: Int64, bindable: @escaping @Sendable (String) -> Bool = { _ in true }) {
        (self.back, self.ignored, self.lastInput, self.bindable) = (back, alreadyHeld, startMs, bindable)
    }

    /// `held`: the device's inputs held now; `guide`: home/guide (or a keyboard's Escape on a
    /// pad's capture) was pressed. Call often.
    public mutating func update(held: Set<String>, nowMs: Int64, guide: Bool = false) -> Outcome {
        if guide { return .cancel(timedOut: false) }
        ignored.formIntersection(held)
        let fresh = held.subtracting(ignored)
        if let input = fresh.subtracting([back]).filter(bindable).sorted().first { return .bind(input) }
        switch (fresh.contains(back), backSince) {
        case (true, nil):
            backSince = nowMs
            lastInput = nowMs
        case let (true, since?) where nowMs - since >= Self.holdMs:
            return .bind(back)
        case (false, _?):
            return .cancel(timedOut: false)
        default:
            break
        }
        if backSince == nil && nowMs - lastInput >= Self.timeoutMs { return .cancel(timedOut: true) }
        return .waiting
    }

    /// The input that is the menu's Back on this kind of device.
    public static func backInput(isKeyboard: Bool) -> String { isKeyboard ? KeyNames.menu : PadInput.east.rawValue }
}
