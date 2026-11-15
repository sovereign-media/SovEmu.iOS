import Foundation
import Testing
@testable import SovEmuKit

/// Controller IDs, labels, mappings, hotkeys and players as `docs/CONTROLLERS.md` in SovEmu
/// describes them (the same cases as the web client's controllers.test.ts).
struct ControllersTests {
    @Test func recognisesKnownModelsByProductCategory() {
        let cases: [(String, String, ControllerFamily)] = [
            ("Xbox One", "xbox", .xbox),
            ("DualSense", "dualsense", .playstation),
            ("DualSense Edge", "dualsense", .playstation),
            ("DualShock 4", "dualshock4", .playstation),
            ("Switch Pro Controller", "switch-pro", .nintendo),
        ]
        for (category, id, family) in cases {
            let identity = ControllerIdentity.identify(productCategory: category, vendorName: "Some Pad")
            #expect(identity.id == id, "\(category)")
            #expect(identity.family == family, "\(category)")
            #expect(identity.name == "Some Pad")
        }
        // Without a vendor name, the category names it.
        #expect(ControllerIdentity.identify(productCategory: "DualSense", vendorName: nil).name == "DualSense")
    }

    @Test func namesOtherControllersByVendorName() {
        let mfi = ControllerIdentity.identify(productCategory: "MFi", vendorName: "8BitDo SN30 Pro+")
        #expect(mfi.id == "pad:name:8bitdo-sn30-pro")
        #expect(mfi.family == .generic)
        let joycon = ControllerIdentity.identify(productCategory: "Switch Joy-Con (L/R)", vendorName: "Joy-Con (L/R)")
        #expect(joycon.id == "pad:name:joy-con-l-r")
        #expect(joycon.family == .nintendo)
        #expect(ControllerIdentity.identify(productCategory: "MFi", vendorName: "Backbone One - PlayStation Edition").family == .playstation)
        #expect(ControllerIdentity.identify(productCategory: "MFi", vendorName: "Xbox Adaptive").family == .xbox)
        // No name at all: the category, else "unknown".
        #expect(ControllerIdentity.identify(productCategory: "MFi", vendorName: "  ").id == "pad:name:mfi")
        #expect(ControllerIdentity.identify(productCategory: "", vendorName: nil).id == "pad:name:unknown")
    }

    @Test func slugsNames() {
        #expect(ControllerIdentity.slug("  Hello,  World!! ") == "hello-world")
        #expect(ControllerIdentity.slug("Manette Élite") == "manette-lite")
        #expect(ControllerIdentity.slug("---") == "")
        let long = ControllerIdentity.slug(String(repeating: "ab ", count: 30))
        #expect(long.count <= 48)
        #expect(!long.hasSuffix("-") && !long.hasPrefix("-"))
        #expect(long == String("ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab-ab".prefix(47)))
        // Every ID the client makes is valid for the server: a-z 0-9 - :, at most 64.
        let id = ControllerIdentity.identify(productCategory: "MFi", vendorName: String(repeating: "Ü x", count: 40)).id
        #expect(id.count <= 64)
        #expect(id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == ":") })
    }

    @Test func labelsInputsByFamily() {
        #expect(PadInput.allCases.map(\.rawValue) == [
            "south", "east", "west", "north", "l1", "r1", "l2", "r2",
            "select", "start", "l3", "r3", "up", "down", "left", "right",
        ])
        let row: (ControllerFamily) -> [String] = { f in [PadInput.south, .east, .west, .north].map(f.label) }
        #expect(row(.xbox) == ["A", "B", "X", "Y"])
        #expect(row(.generic) == ["A", "B", "X", "Y"])
        #expect(row(.playstation) == ["✕", "○", "□", "△"])
        #expect(row(.nintendo) == ["B", "A", "Y", "X"])
        let rest: (ControllerFamily) -> [String] = { f in [PadInput.l1, .r1, .l2, .r2, .select, .start, .l3, .r3].map(f.label) }
        #expect(rest(.xbox) == ["LB", "RB", "LT", "RT", "View", "Menu", "LS", "RS"])
        #expect(rest(.playstation) == ["L1", "R1", "L2", "R2", "Create", "Options", "L3", "R3"])
        #expect(rest(.nintendo) == ["L", "R", "ZL", "ZR", "−", "+", "LS", "RS"])
        #expect(ControllerFamily.playstation.label(.up) == "D-pad ↑")
        #expect(inputLabel("KeyZ", family: nil) == "Z")
        #expect(inputLabel("south", family: .playstation) == "✕")
    }

    @Test func defaultMappings() {
        let pad = ControllerMap.defaults(for: "dualsense")
        #expect(pad.state(["south"]) == RetroButton.b.bit)
        #expect(pad.state(["east"]) == RetroButton.a.bit)
        #expect(pad.state(["west"]) == RetroButton.y.bit)
        #expect(pad.state(["north"]) == RetroButton.x.bit)
        #expect(pad.state(["l1", "r1", "l2", "r2"]) == RetroButton.l.bit | RetroButton.r.bit | RetroButton.l2.bit | RetroButton.r2.bit)
        #expect(pad.state(["select", "start", "l3", "r3"]) == RetroButton.select.bit | RetroButton.start.bit | RetroButton.l3.bit | RetroButton.r3.bit)
        #expect(pad.state(["up", "down", "left", "right"]) == RetroButton.up.bit | RetroButton.down.bit | RetroButton.left.bit | RetroButton.right.bit)
        #expect(pad.bindings.count == 16)

        let keys = ControllerMap.defaults(for: "keyboard")
        #expect(keys.state(["KeyZ"]) == RetroButton.b.bit)
        #expect(keys.state(["KeyX"]) == RetroButton.a.bit)
        #expect(keys.state(["KeyA", "KeyS", "KeyQ", "KeyW"]) == RetroButton.y.bit | RetroButton.x.bit | RetroButton.l.bit | RetroButton.r.bit)
        #expect(keys.state(["Enter"]) == RetroButton.start.bit)
        #expect(keys.inputs(for: .select) == ["ShiftLeft", "ShiftRight"])
        #expect(keys.state(["ArrowUp", "ArrowLeft"]) == RetroButton.up.bit | RetroButton.left.bit)
        #expect(keys.state(["Tab", "Backspace", "KeyP"]) == 0)
    }

    @Test func rebindsAndConvertsToTheApi() {
        // Swap A and B on a pad.
        let swapped = ControllerMap.pad.rebinding("south", to: .a).rebinding("east", to: .b)
        #expect(swapped.state(["south"]) == RetroButton.a.bit)
        #expect(swapped.state(["east"]) == RetroButton.b.bit)
        #expect(swapped.inputs(for: .a) == ["south"])
        // A button keeps just its new input; the input leaves its old button.
        let select = ControllerMap.keyboard.rebinding("KeyP", to: .select)
        #expect(select.inputs(for: .select) == ["KeyP"])
        #expect(select.bindings["ShiftLeft"] == nil)
        let moved = ControllerMap.pad.rebinding("north", to: .b)
        #expect(moved.inputs(for: .x).isEmpty && moved.inputs(for: .b) == ["north"])

        let bindings = swapped.bindingInputs
        #expect(bindings.count == 16)
        #expect(bindings.first == ControllerBinding(input: "down", button: "DOWN"))
        #expect(ControllerMap(bindings: bindings) == swapped)
        #expect(ControllerMap(bindings: [ControllerBinding(input: "south", button: "TURBO")]).bindings.isEmpty)
        #expect(RetroButton.allCases.map(\.name) == ["B", "Y", "SELECT", "START", "UP", "DOWN", "LEFT", "RIGHT", "A", "X", "L", "R", "L2", "R2", "L3", "R3"])
    }

    @Test func namesKeyCodesLikeKeyboardEvent() {
        // HID usages, as GCKeyCode's raw values.
        #expect(KeyNames.code(forUsage: 0x04) == "KeyA")
        #expect(KeyNames.code(forUsage: 0x1d) == "KeyZ")
        #expect(KeyNames.code(forUsage: 0x1e) == "Digit1")
        #expect(KeyNames.code(forUsage: 0x26) == "Digit9")
        #expect(KeyNames.code(forUsage: 0x27) == "Digit0")
        #expect(KeyNames.code(forUsage: 0x28) == "Enter")
        #expect(KeyNames.code(forUsage: 0x29) == "Escape")
        #expect(KeyNames.code(forUsage: 0x2a) == "Backspace")
        #expect(KeyNames.code(forUsage: 0x2b) == "Tab")
        #expect(KeyNames.code(forUsage: 0x2c) == "Space")
        #expect(KeyNames.code(forUsage: 0x4f) == "ArrowRight")
        #expect(KeyNames.code(forUsage: 0x50) == "ArrowLeft")
        #expect(KeyNames.code(forUsage: 0x51) == "ArrowDown")
        #expect(KeyNames.code(forUsage: 0x52) == "ArrowUp")
        #expect(KeyNames.code(forUsage: 0xe0) == "ControlLeft")
        #expect(KeyNames.code(forUsage: 0xe1) == "ShiftLeft")
        #expect(KeyNames.code(forUsage: 0xe2) == "AltLeft")
        #expect(KeyNames.code(forUsage: 0xe4) == "ControlRight")
        #expect(KeyNames.code(forUsage: 0xe5) == "ShiftRight")
        #expect(KeyNames.code(forUsage: 0xe6) == "AltRight")
        #expect(KeyNames.code(forUsage: 0x3a) == "F1")
        #expect(KeyNames.code(forUsage: 0x45) == "F12")
        #expect(KeyNames.code(forUsage: 0x58) == "NumpadEnter")
        #expect(KeyNames.code(forUsage: 0x59) == "Numpad1")
        #expect(KeyNames.code(forUsage: 0x62) == "Numpad0")
        #expect(KeyNames.code(forUsage: 0x00) == nil)
        // Every name fits the server's limit and has no spaces.
        for usage in KeyNames.allUsages {
            let code = try! #require(KeyNames.code(forUsage: usage))
            #expect(code.count <= 32 && !code.contains(" "))
        }
        #expect(!KeyNames.bindable("Tab") && !KeyNames.bindable("Backspace"))
        #expect(KeyNames.bindable("Escape") && KeyNames.bindable("KeyZ"))
        #expect(KeyNames.label("ArrowUp") == "↑")
        #expect(KeyNames.label("Digit7") == "7")
        #expect(KeyNames.label("ShiftLeft") == "Left Shift")
        #expect(KeyNames.label("AltRight") == "Right Option")
        #expect(KeyNames.label("Space") == "Space")
    }

    @Test func readsHotkeysAfterMapping() {
        let select = RetroButton.select.bit, l = RetroButton.l.bit, r = RetroButton.r.bit
        let start = RetroButton.start.bit, b = RetroButton.b.bit

        let ff = HotkeyReading.read(select | r | b)
        #expect(ff.fastForward && !ff.rewind && !ff.menu)
        #expect(ff.state == b, "SELECT and R are kept from the game")
        let rewind = HotkeyReading.read(select | l)
        #expect(rewind.rewind && !rewind.fastForward && rewind.state == 0)
        let menu = HotkeyReading.read(select | start)
        #expect(menu.menu && menu.state == 0)
        let plain = HotkeyReading.read(r | l | start)
        #expect(!plain.fastForward && !plain.rewind && !plain.menu && plain.state == r | l | start)

        // A remapped pad: the combo follows the RetroPad buttons, not the physical ones.
        let remapped = ControllerMap.pad.rebinding("north", to: .select).rebinding("east", to: .r)
        let state = remapped.state(["north", "east"])
        #expect(HotkeyReading.read(state).fastForward)
        #expect(!HotkeyReading.read(remapped.state(["select", "r1"])).fastForward, "physical select and r1 are unbound now")
    }

    @Test func assignsTheLowestFreePlayer() {
        var players = Players<String>()
        #expect(players.join("a") == 0)
        #expect(players.join("b") == 1)
        #expect(players.join("c") == 2)
        #expect(players.join("a") == 0, "known controllers keep their port")
        players.leave("b")
        #expect(players.port("b") == nil)
        #expect(players.join("d") == 1, "a disconnect frees its player")
        #expect(players.join("e") == 3)
        #expect(players.join("f") == 3, "past four players, the last one")
        players.set("a", port: 2)
        #expect(players.port("a") == 2)
        players.set("a", port: 9)
        #expect(players.port("a") == 3)
        players.leave("a")
        players.leave("e")
        players.leave("f")
        #expect(players.join("g") == 0)
    }

    @Test func watchesForNewPressesAndMenuActions() {
        var watcher = PressWatcher(holding: ["south"])
        #expect(watcher.pressed(["south"]).isEmpty, "held when watching began")
        #expect(watcher.pressed(["south", "east"]) == ["east"])
        #expect(watcher.pressed([]).isEmpty)
        #expect(watcher.pressed(["south"]) == ["south"])
        #expect(MenuAction.of("south") == .confirm)
        #expect(MenuAction.of("east") == .back)
        #expect(MenuAction.of("Escape") == .back)
        #expect(MenuAction.of("ArrowDown") == .down)
        #expect(MenuAction.of("l1") == nil)
    }

    /// A server layering mappings as `controllerMappings(system:)` does: the user's own for the
    /// system, their own for every system, the default for the system, the default for every
    /// system. Keys are `controller@system`, with `*` for every system.
    private actor FakeServer: ControllerMappingService {
        var own: [String: [ControllerBinding]]
        let defaults: [String: [ControllerBinding]]
        private(set) var calls: [String] = []

        init(own: [String: ControllerMap], defaults: [String: ControllerMap]) {
            self.own = own.mapValues(\.bindingInputs)
            self.defaults = defaults.mapValues(\.bindingInputs)
        }

        func controllerMappings(system: String?) async throws -> [ControllerMapping] {
            calls.append("list \(system ?? "*")")
            let models = Set((Array(own.keys) + Array(defaults.keys)).map { String($0.split(separator: "@")[0]) })
            typealias Layer = (scope: String?, source: MappingSource, table: [String: [ControllerBinding]])
            var layers: [Layer] = []
            if let system { layers.append((system, .user, own)) }
            layers.append((nil, .user, own))
            if let system { layers.append((system, .admin, defaults)) }
            layers.append((nil, .admin, defaults))
            return models.compactMap { model in
                for (scope, source, table) in layers {
                    if let bindings = table["\(model)@\(scope ?? "*")"] {
                        return ControllerMapping(controller: model, system: scope, name: model, bindings: bindings, source: source)
                    }
                }
                return nil
            }
        }

        func saveControllerMapping(controller: String, system: String?, name: String, bindings: [ControllerBinding]) async throws
            -> ControllerMapping
        {
            calls.append("save \(controller)@\(system ?? "*")")
            own["\(controller)@\(system ?? "*")"] = bindings
            return ControllerMapping(controller: controller, system: system, name: name, bindings: bindings, source: .user)
        }

        func resetControllerMapping(controller: String, system: String?) async throws -> Bool {
            calls.append("reset \(controller)@\(system ?? "*")")
            return own.removeValue(forKey: "\(controller)@\(system ?? "*")") != nil
        }
    }

    @Test func resetRefetchesSoTheNextLayerApplies() async throws {
        let mine = ControllerMap.pad.rebinding("south", to: .a)
        let mineEverywhere = ControllerMap.pad.rebinding("west", to: .start)
        let admin = ControllerMap.pad.rebinding("north", to: .start)
        let server = FakeServer(
            own: ["dualsense@megadrive": mine, "dualsense@*": mineEverywhere, "keyboard@megadrive": ControllerMap.keyboard.rebinding("KeyP", to: .start)],
            defaults: ["dualsense@megadrive": admin, "xbox@*": admin])
        let start = try await Mappings.fetch(system: "megadrive", with: server)
        #expect(start.mapping(for: "dualsense") == mine)
        #expect(start.origin(for: "dualsense", in: .system("megadrive")) == .yoursForThisSystem)
        #expect(start.origin(for: "dualsense", in: .everySystem) == .yoursForAllSystems)
        #expect(start.origin(for: "xbox", in: .system("megadrive")) == .defaults)
        #expect(start.mapping(for: "xbox") == admin)

        // Resetting this system's: the user's own for every system comes next, not a default.
        let first = try await start.resetting("dualsense", in: .system("megadrive"), with: server)
        // Reset first, then both lists (fetched together, in either order).
        let calls = await server.calls.suffix(3)
        #expect(calls.first == "reset dualsense@megadrive")
        #expect(Set(calls.dropFirst()) == ["list megadrive", "list *"])
        #expect(first.mapping(for: "dualsense") == mineEverywhere)
        #expect(first.origin(for: "dualsense", in: .system("megadrive")) == .yoursForAllSystems)
        #expect(!first.canReset("dualsense", in: .system("megadrive")) && first.canReset("dualsense", in: .everySystem))

        // Then every system's: the system's default (an admin's), not the built-in mapping.
        let second = try await first.resetting("dualsense", in: .everySystem, with: server)
        #expect(await server.calls.contains("reset dualsense@*"))
        #expect(second.mapping(for: "dualsense") == admin)
        #expect(second.origin(for: "dualsense", in: .system("megadrive")) == .defaults)
        #expect(second.mapping(for: "dualsense", in: .everySystem) == .pad, "no default for every system: built-in")
        #expect(second.mapping(for: "keyboard").inputs(for: .start) == ["KeyP"], "other models are kept")

        // Nothing left at all: the built-in defaults.
        let third = try await second.resetting("keyboard", in: .system("megadrive"), with: server)
        #expect(third.mapping(for: "keyboard") == .keyboard)
        #expect(third.inSystem.entry(for: "keyboard") == nil)
    }

    @Test func savesInTheChosenScope() async throws {
        let server = FakeServer(own: [:], defaults: ["xbox@megadrive": ControllerMap.pad.rebinding("north", to: .start)])
        let start = try await Mappings.fetch(system: "megadrive", with: server)
        let edit = ControllerMap.pad.rebinding("south", to: .a)

        let everywhere = try await start.saving(edit, for: "xbox", name: "Xbox", in: .everySystem, with: server)
        #expect(await server.calls.contains("save xbox@*"))
        // The user's own for every system beats the system's default.
        #expect(everywhere.mapping(for: "xbox") == edit)
        #expect(everywhere.origin(for: "xbox", in: .system("megadrive")) == .yoursForAllSystems)

        let here = try await everywhere.saving(.pad, for: "xbox", name: "Xbox", in: .system("megadrive"), with: server)
        #expect(await server.calls.contains("save xbox@megadrive"))
        #expect(here.mapping(for: "xbox") == .pad && here.mapping(for: "xbox", in: .everySystem) == edit)
        #expect(here.origin(for: "xbox", in: .system("megadrive")) == .yoursForThisSystem)
    }

    @Test func appliesChangesLocallyByTheSameLayers() {
        var m = Mappings(system: "snes")
        let edit = ControllerMap.pad.rebinding("south", to: .a)
        m = m.applying(edit, for: "xbox", in: .everySystem)
        #expect(m.mapping(for: "xbox") == edit && m.origin(for: "xbox", in: .system("snes")) == .yoursForAllSystems)
        m = m.applying(.pad, for: "xbox", in: .system("snes"))
        #expect(m.mapping(for: "xbox") == .pad && m.origin(for: "xbox", in: .system("snes")) == .yoursForThisSystem)
        // A later every-system change does not override this system's own.
        m = m.applying(edit, for: "xbox", in: .everySystem)
        #expect(m.mapping(for: "xbox") == .pad && m.mapping(for: "xbox", in: .everySystem) == edit)
    }

    @Test func namesScopesAndOrigins() {
        #expect(MappingOrigin.yoursForThisSystem.text == "Yours for this system")
        #expect(MappingOrigin.yoursForAllSystems.text == "Yours for all systems")
        #expect(MappingOrigin.defaults.text == "Default")
        let m = Mappings(system: "nes")
        #expect(m.origin(for: "xbox", in: .system("nes")) == .defaults, "built-in is a default")
        #expect(!m.canReset("xbox", in: .system("nes")) && !m.canReset("xbox", in: .everySystem))
    }

    @Test func highlightsTheButtonOnBothDiagrams() {
        // Mega Drive "C" is RetroPad A; by default south (✕) drives B and east drives A.
        let lit = DiagramHighlight(button: .a, mapping: .pad)
        #expect(lit.systemKeys == ["A"] && lit.controllerKeys == ["east"])
        let two = ControllerMap.pad.rebinding("south", to: .a)
        let both = ControllerMap(two.bindings.merging(["r1": .a]) { $1 })
        #expect(DiagramHighlight(button: .a, mapping: both).controllerKeys == ["south", "r1"])
        #expect(DiagramHighlight(button: .b, mapping: two).controllerKeys.isEmpty, "B lost its input")
        // A keyboard mapping lights nothing on a controller diagram.
        #expect(DiagramHighlight(button: .b, mapping: .keyboard).controllerKeys.isEmpty)
        #expect(DiagramHighlight(button: nil, mapping: .pad) == DiagramHighlight(button: nil, mapping: .keyboard))
    }

    @Test func listsTheSystemsButtonsForThisSystemAndAllSixteenOtherwise() throws {
        let info = try SovEmuAPI.decodeData(ControlsInfo.self, from: Data(Fixtures.megadriveControls.utf8), status: 200)
        let here = remapButtons(info.controls, scope: .system("megadrive"))
        #expect(here.count == 12)
        #expect(here.first { $0.button == "A" }?.label == "C")
        let every = remapButtons(info.controls, scope: .everySystem)
        #expect(every.count == 16 && every.first == SystemButton(button: "B", label: "B"))
        #expect(every.first { $0.button == "SELECT" }?.label == "Select")
        #expect(remapButtons(nil, scope: .system("megadrive")).count == 16, "no controls: RetroPad names")
    }
}
