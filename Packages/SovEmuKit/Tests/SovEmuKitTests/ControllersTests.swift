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
}
