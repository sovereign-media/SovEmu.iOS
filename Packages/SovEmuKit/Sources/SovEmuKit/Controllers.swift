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

    /// Every named key's usage, for polling a keyboard.
    public static var allUsages: [Int] { usages.keys.sorted() }

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

/// An input as its device labels it: a pad input by family (`✕`, `LB`), else a key's name.
public func inputLabel(_ input: String, family: ControllerFamily?) -> String {
    if let family, let pad = PadInput(rawValue: input) { return family.label(pad) }
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

/// The mappings in force for a user, as `controllerMappings` returns them: their own, else the
/// server's default for the model. A model the server does not list uses the built-in defaults.
public struct MappingStore: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let map: ControllerMap
        public let source: MappingSource
    }

    private var entries: [String: Entry]

    public init(_ mappings: [ControllerMapping] = []) {
        entries = Dictionary(mappings.map { ($0.controller, Entry(map: ControllerMap(bindings: $0.bindings), source: $0.source)) }) { $1 }
    }

    /// The mapping in force for a controller model.
    public func mapping(for controller: String) -> ControllerMap {
        entries[controller]?.map ?? .defaults(for: controller)
    }

    /// Where it comes from; nil for the built-in defaults.
    public func source(for controller: String) -> MappingSource? { entries[controller]?.source }

    /// The user changed a model's mapping (saved, or being saved, as theirs).
    public mutating func setUser(_ controller: String, _ map: ControllerMap) {
        entries[controller] = Entry(map: map, source: .user)
    }

    /// What the server answered to a save.
    public mutating func record(_ mapping: ControllerMapping) {
        entries[mapping.controller] = Entry(map: ControllerMap(bindings: mapping.bindings), source: mapping.source)
    }

    /// Removes the user's own mapping for a model on the server, then reads back every mapping
    /// in force: the model falls back to the server's default if there is one, and only
    /// otherwise to the built-in defaults.
    public static func reset(_ controller: String, with service: some ControllerMappingService) async throws -> MappingStore {
        _ = try await service.resetControllerMapping(controller: controller)
        return MappingStore(try await service.controllerMappings())
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
