// The in-game menu's Controllers pages on a TV, as SovEmu.Android's `ControllersScreen`
// (`Controllers.kt`: the device list, then one device's bindings beside the console's pad and the
// player's controller) and its moulded `PadDiagram` (`Diagram.kt`), at 1.5 points to the dp. The
// rows and their navigation are the shared `GameMenu`'s; this only draws them.
import SovEmuKit
import SwiftUI

/// One Android TV dp (or sp) in tvOS points: Android lays the TV out 1280 dp wide, tvOS 1920.
private func dp(_ value: CGFloat) -> CGFloat { value * 1.5 }

/// Android's `Sov.Muted`.
private let muted = Color(hex: 0x8B93A7)

/// The panel both pages sit on.
private extension View {
    func controllersPanel() -> some View {
        padding(dp(20))
            .background(Sov.panel, in: RoundedRectangle(cornerRadius: dp(16)))
            .overlay(RoundedRectangle(cornerRadius: dp(16)).strokeBorder(Sov.edge, lineWidth: dp(1)))
    }
}

/// A gamepad in an accent circle: a device's mark.
private struct DeviceMark: View {
    var body: some View {
        Image(systemName: "gamecontroller").font(.system(size: dp(17))).foregroundStyle(Sov.accent)
            .frame(width: dp(40), height: dp(40))
            .background(Sov.accent.opacity(0.2), in: Circle())
    }
}

// MARK: - The device list

/// Every connected device with its player (left and right change it, for this session) and its
/// Buttons (a click opens them), then Done.
struct TVControllerList: View {
    let devices: [Controller.Device]
    let items: [MenuItem]
    let focus: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: dp(10)) {
                Image(systemName: "gamecontroller").font(.system(size: dp(20))).foregroundStyle(Sov.accent)
                Text("Controllers").font(.system(size: dp(22), weight: .bold)).foregroundStyle(.white)
            }
            Text("Each controller is its own player; choose another for this session. A player is only ever one device. "
                + "The keyboard is player 1 unless moved.")
                .font(.system(size: dp(13))).foregroundStyle(muted).lineSpacing(dp(5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, dp(6)).padding(.bottom, dp(12))
            VStack(spacing: dp(10)) {
                if devices.isEmpty {
                    Text("No controller or keyboard connected.").font(.system(size: dp(14))).foregroundStyle(Sov.slate300)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, dp(8))
                }
                ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                    card(device, focused: items.indices.contains(focus) && focus == index && items[focus].id != "back")
                }
            }
            TVButtonLabel(title: "Done", symbol: "checkmark", focused: items.indices.contains(focus) && items[focus].id == "back")
                .padding(.top, dp(14))
        }
        .frame(width: dp(560))
        .controllersPanel()
    }

    private func card(_ device: Controller.Device, focused: Bool) -> some View {
        VStack(alignment: .leading, spacing: dp(10)) {
            HStack(spacing: dp(12)) {
                DeviceMark()
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.identity.name).font(.system(size: dp(16), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(device.identity.isKeyboard ? "Keyboard" : device.identity.family.displayName)
                        .font(.system(size: dp(12))).foregroundStyle(Sov.slate400)
                }
                Spacer(minLength: 0)
                TVButtonLabel(title: "Buttons", symbol: "slider.horizontal.3", variant: .glass, focused: focused, large: false, wide: false)
            }
            HStack(spacing: dp(6)) {
                TVEyebrow(text: "Player").padding(.trailing, dp(6))
                ForEach(0..<WireProtocol.maxPorts, id: \.self) { port in
                    PlayerToggle(number: port + 1, on: device.port == port)
                }
                if focused {
                    Text("◀ ▶ to change").font(.system(size: dp(12))).foregroundStyle(Sov.slate400).padding(.leading, dp(6))
                }
            }
        }
        .padding(dp(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sov.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: dp(12)))
        .overlay(
            RoundedRectangle(cornerRadius: dp(12))
                .strokeBorder(focused ? .white.opacity(0.6) : .white.opacity(0.08), lineWidth: dp(focused ? 2 : 1)))
    }
}

/// A player's pill, as Android's `Toggle`: the accent, with a tick, when it is the device's.
private struct PlayerToggle: View {
    let number: Int
    let on: Bool

    var body: some View {
        HStack(spacing: dp(6)) {
            if on { Image(systemName: "checkmark").font(.system(size: dp(12), weight: .bold)) }
            Text("\(number)").font(.system(size: dp(14), weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, dp(12))
        .frame(height: dp(32))
        .background(on ? Sov.accent : .clear, in: Capsule())
        .overlay { if !on { Capsule().strokeBorder(.white.opacity(0.15), lineWidth: dp(1)) } }
    }
}

// MARK: - One device's bindings

/// A device's page, nearly the whole screen: the device and what is in force, the scope as a
/// strip of chips (the first row: left and right change it), a banner saying what to do, the
/// console's pad and the player's controller beside the buttons (the focused one lit on both),
/// and Reset and Back at the foot.
struct TVDevicePage: View {
    let menu: GameMenu
    let items: [MenuItem]

    var body: some View {
        let focus = menu.focus
        let focusedId = items.indices.contains(focus) ? items[focus].id : nil
        let rows = Array(items.enumerated()).filter { !["scope", "reset", "back", "player"].contains($0.element.id) }
        let diagrams = menu.diagrams(items)
        GeometryReader { screen in
            VStack(alignment: .leading, spacing: 0) {
                header(scopeFocused: focusedId == "scope")
                banner(rows: rows)
                GeometryReader { area in
                    let w = area.size.width
                    let h = area.size.height
                    if let diagrams {
                        // The pads beside the buttons, side by side or stacked, whichever draws larger.
                        let pads = w * 0.6
                        let sideBySide = min(pads / 2 / 160, h / 100) >= min(pads / 160, h / 2 / 100)
                        HStack(spacing: dp(12)) {
                            DiagramPanels(diagrams: diagrams, sideBySide: sideBySide)
                                .frame(width: (w - dp(12)) * 0.6)
                            bindingList(rows, focus: focus)
                        }
                    } else {
                        bindingList(rows, focus: focus)
                    }
                }
                HStack(spacing: dp(8)) {
                    Spacer()
                    if let reset = items.firstIndex(where: { $0.id == "reset" }) {
                        TVButtonLabel(title: "Reset to defaults", symbol: "arrow.counterclockwise", variant: .outline,
                                      focused: reset == focus, wide: false)
                    }
                    TVButtonLabel(title: "Back", symbol: "chevron.left", focused: focusedId == "back", wide: false)
                }
                .padding(.top, dp(12))
            }
            .controllersPanel()
            .frame(width: screen.size.width * 0.97, height: screen.size.height * 0.96)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func header(scopeFocused: Bool) -> some View {
        HStack(spacing: dp(12)) {
            DeviceMark()
            VStack(alignment: .leading, spacing: 0) {
                Text(menu.openDevice?.identity.name ?? "").font(.system(size: dp(20), weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1)
                if let device = menu.openDevice {
                    Text("In force here: \(menu.inForce(device))").font(.system(size: dp(12))).foregroundStyle(Sov.slate400)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: dp(2)) {
                ScopeChip(title: "This system (\(menu.system.short))", symbol: "gamecontroller", on: !menu.editsEverySystem,
                          focused: scopeFocused && !menu.editsEverySystem)
                ScopeChip(title: "All systems", symbol: "square.grid.2x2", on: menu.editsEverySystem,
                          focused: scopeFocused && menu.editsEverySystem)
            }
            .padding(dp(4))
            .background(Sov.surface.opacity(0.9), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: dp(1)))
        }
    }

    /// What to do now: a bright banner while waiting for an input, else a quiet hint (or the
    /// last word: saved, not saved).
    private func banner(rows: [(offset: Int, element: MenuItem)]) -> some View {
        let capture = menu.capture
        return HStack(spacing: dp(10)) {
            Image(systemName: capture == nil ? "exclamationmark.circle" : "gamecontroller").font(.system(size: dp(16)))
                .foregroundStyle(capture == nil ? Sov.slate400 : .white)
            if let capture {
                let back = capture.identity.isKeyboard ? "Esc" : capture.identity.family.label(.east)
                Text("Press a button for ").font(.system(size: dp(15))).foregroundStyle(.white)
                KeyCap(text: capture.label, accent: true)
                Text("  ·  tap \(back) to cancel, hold it to bind \(back)").font(.system(size: dp(13))).foregroundStyle(Sov.slate300)
            } else {
                Text(menu.note ?? "Pick a button, then press what should drive it.").font(.system(size: dp(14)))
                    .foregroundStyle(Sov.slate300)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, dp(14)).padding(.vertical, dp(10))
        .background(capture == nil ? .white.opacity(0.04) : Sov.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: dp(10)))
        .overlay { if capture != nil { RoundedRectangle(cornerRadius: dp(10)).strokeBorder(Sov.accent, lineWidth: dp(1)) } }
        .padding(.vertical, dp(12))
    }

    private func bindingList(_ rows: [(offset: Int, element: MenuItem)], focus: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: dp(4)) {
                    ForEach(rows, id: \.element.id) { index, item in
                        BindingRow(item: item, focused: index == focus,
                                   capturing: menu.capture != nil && menu.capture?.button.name == item.id)
                            .id(item.id)
                    }
                }
            }
            .onChange(of: focus, initial: true) { _, new in
                if items.indices.contains(new) { withAnimation { proxy.scrollTo(items[new].id, anchor: .center) } }
            }
        }
    }
}

/// A scope's chip: quiet at rest, filled when it is the one in use, ringed when the row has the
/// focus.
private struct ScopeChip: View {
    let title: String
    let symbol: String
    let on: Bool
    let focused: Bool

    var body: some View {
        HStack(spacing: dp(6)) {
            Image(systemName: symbol).font(.system(size: dp(13)))
            Text(title).font(.system(size: dp(14), weight: on ? .semibold : .regular)).lineLimit(1)
        }
        .foregroundStyle(on || focused ? .white : Sov.slate400)
        .padding(.horizontal, dp(14))
        .frame(height: dp(32))
        .background(on ? .white.opacity(0.15) : .clear, in: Capsule())
        .overlay { if focused { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: dp(2)) } }
    }
}

/// A key cap: how an input or a console button is shown (the accent while it is being bound).
private struct KeyCap: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text).font(.system(size: dp(13), weight: .bold)).foregroundStyle(.white).lineLimit(1)
            .padding(.horizontal, dp(8)).padding(.vertical, dp(3))
            .background(accent ? Sov.accent : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: dp(6)))
            .overlay(RoundedRectangle(cornerRadius: dp(6)).strokeBorder(.white.opacity(accent ? 0.4 : 0.15), lineWidth: dp(1)))
    }
}

/// One of the system's buttons and what drives it: the console's label, then the bound inputs as
/// key caps. Focus fills it with the accent; waiting for an input, it says so.
private struct BindingRow: View {
    let item: MenuItem
    let focused: Bool
    let capturing: Bool

    var body: some View {
        HStack(spacing: dp(8)) {
            Text(item.title).font(.system(size: dp(15), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 0)
            let keys = item.keys ?? []
            if capturing {
                Text("Press an input…").font(.system(size: dp(13))).foregroundStyle(.white)
            } else if keys.isEmpty {
                Text("Not bound").font(.system(size: dp(13))).foregroundStyle(Sov.slate500)
            } else {
                ForEach(Array(keys.prefix(3).enumerated()), id: \.offset) { _, key in KeyCap(text: key) }
            }
        }
        .padding(.horizontal, dp(12))
        .frame(height: dp(48))
        .background(
            capturing ? Sov.accent.opacity(0.35) : focused ? Sov.accent.opacity(0.22) : .clear,
            in: RoundedRectangle(cornerRadius: dp(10)))
        .overlay {
            if focused || capturing {
                RoundedRectangle(cornerRadius: dp(10))
                    .strokeBorder(capturing ? Sov.accent : .white.opacity(0.6), lineWidth: dp(2))
            }
        }
    }
}

/// The console's pad and the player's controller, each on its own panel, side by side or stacked.
private struct DiagramPanels: View {
    let diagrams: GameMenu.Diagrams
    let sideBySide: Bool

    var body: some View {
        if sideBySide {
            HStack(spacing: dp(8)) { panels }
        } else {
            VStack(spacing: dp(8)) { panels }
        }
    }

    @ViewBuilder private var panels: some View {
        if let system = diagrams.system { panel(system, diagrams.highlight.systemKeys) }
        if let controller = diagrams.controller {
            panel(controller, diagrams.highlight.controllerKeys)
        } else {
            Text("Keyboard: keys are listed by name.").font(.system(size: dp(13))).foregroundStyle(Sov.slate400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Sov.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: dp(12)))
        }
    }

    private func panel(_ layout: PadLayout, _ lit: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: dp(2)) {
            Text(layout.name).font(.system(size: dp(12))).foregroundStyle(muted).padding(.leading, dp(4))
            TVPadDiagram(layout: layout, lit: lit)
        }
        .padding(dp(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Sov.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: dp(12)))
    }
}

// MARK: - The moulded pad

private let bodyTop = Color(hex: 0x3A4357)
private let bodyBottom = Color(hex: 0x222836)
private let recessFill = Color(hex: 0x12151C)
private let keyTop = Color(hex: 0x5A647B)
private let keyBottom = Color(hex: 0x3A4255)
private let stickCap = Color(hex: 0x2A303D)
private let litFill = Color(hex: 0x4169E1)
/// The four D-pad keys, on a system's pad (RetroPad names) or a controller's (input names).
private let dpadKeys: Set<String> = ["UP", "DOWN", "LEFT", "RIGHT", "up", "down", "left", "right"]
private let stickKeys: Set<String> = ["L3", "R3", "l3", "r3"]

/// Face-button label colours by family, as the controllers print them.
private func faceColour(_ family: String, _ key: String) -> Color? {
    switch (family, key) {
    case ("xbox", "south"), ("generic", "south"): Color(hex: 0x4ADE80)
    case ("xbox", "east"), ("generic", "east"): Color(hex: 0xF87171)
    case ("xbox", "west"), ("generic", "west"): Color(hex: 0x60A5FA)
    case ("xbox", "north"), ("generic", "north"): Color(hex: 0xFACC15)
    case ("playstation", "south"): Color(hex: 0x93C5FD)
    case ("playstation", "east"): Color(hex: 0xFCA5A5)
    case ("playstation", "west"): Color(hex: 0xF9A8D4)
    case ("playstation", "north"): Color(hex: 0x86EFAC)
    default: nil
    }
}

/// A pad from the server's layout, drawn to look moulded rather than flat, as SovEmu.Android's
/// `PadDiagram`: the body's shapes merged into one shadowed, shaded silhouette with an edge;
/// recesses sunk into it; the D-pad as one cross; sticks as capped domes; face buttons in the
/// family's colours. The `lit` keys are the accent with a white edge.
struct TVPadDiagram: View {
    let layout: PadLayout
    let lit: Set<String>

    var body: some View {
        Canvas { context, size in
            let box = layout.visibleBounds
            let k = min(size.width / box.w, size.height / box.h)
            let dx = (size.width - box.w * k) / 2
            let dy = (size.height - box.h * k) / 2
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: dx + (x - box.x) * k, y: dy + (y - box.y) * k, width: w * k, height: h * k)
            }
            func rounded(_ r: CGRect, _ radius: Double) -> Path {
                Path(roundedRect: r, cornerRadius: min(radius * k, min(r.width, r.height) / 2))
            }
            func vertical(_ top: Color, _ bottom: Color, _ r: CGRect) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: r.midX, y: r.minY),
                                endPoint: CGPoint(x: r.midX, y: r.maxY))
            }

            // The body: one silhouette, shadowed, shaded top to bottom, with a faint edge.
            var silhouette = Path()
            for shape in layout.body where shape.tone == 0 {
                silhouette = silhouette.union(rounded(rect(shape.x, shape.y, shape.w, shape.h), shape.r))
            }
            let bounds = silhouette.boundingRect
            context.fill(silhouette.offsetBy(dx: 0, dy: dp(2.5)), with: .color(.black.opacity(0.35)))
            context.fill(silhouette, with: vertical(bodyTop, bodyBottom, bounds))
            context.stroke(silhouette, with: .color(.white.opacity(0.08)), lineWidth: dp(1))
            for shape in layout.body where shape.tone == 1 {
                let p = rounded(rect(shape.x, shape.y, shape.w, shape.h), shape.r)
                context.fill(p, with: .color(recessFill))
                context.stroke(p, with: .color(.black.opacity(0.4)), lineWidth: dp(1))
            }

            // The D-pad as one cross under its arms (its keys are four separate squares).
            let dpad = layout.keys.filter { dpadKeys.contains($0.key) }
            func arm(_ name: String) -> PadKey? { dpad.first { $0.key.lowercased() == name } }
            if dpad.count == 4, let up = arm("up"), let down = arm("down"), let left = arm("left"), let right = arm("right") {
                let column = rect(up.x, up.y, up.w, down.y + down.h - up.y)
                let row = rect(left.x, left.y, right.x + right.w - left.x, left.h)
                for r in [column, row] {
                    context.fill(Path(roundedRect: r, cornerRadius: 1.5 * k), with: vertical(keyTop, keyBottom, column))
                }
            }

            for key in layout.keys {
                let on = lit.contains(key.key)
                let r = rect(key.x, key.y, key.w, key.h)
                let p = rounded(r, key.r)
                if dpadKeys.contains(key.key) {
                    if on { context.fill(p, with: .color(litFill)) }
                } else if stickKeys.contains(key.key) {
                    drawStick(&context, r, on)
                } else {
                    context.fill(p, with: on ? .color(litFill) : vertical(keyTop, keyBottom, r))
                    context.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: dp(0.75))
                }
                if on { context.stroke(p, with: .color(.white), lineWidth: dp(1.5)) }
                // The label, as large as fits: by its height, and by its width for longer labels.
                guard !key.label.isEmpty else { continue }
                let px = min(key.h * 0.62, key.w * 1.5 / Double(max(1, key.label.count))) * k
                let colour = on ? Color.white : faceColour(layout.id, key.key) ?? .white
                context.draw(Text(key.label).font(.system(size: max(4, px), weight: .bold)).foregroundStyle(colour),
                             at: CGPoint(x: r.midX, y: r.midY))
            }
        }
        .accessibilityLabel(layout.name)
    }

    /// A stick: a dark cap with a lighter, concave top.
    private func drawStick(_ context: inout GraphicsContext, _ r: CGRect, _ on: Bool) {
        let c = CGPoint(x: r.midX, y: r.midY)
        let radius = r.width / 2
        let outer = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        let inner = Path(ellipseIn: CGRect(x: c.x - radius * 0.7, y: c.y - radius * 0.7, width: radius * 1.4, height: radius * 1.4))
        context.fill(outer, with: .color(on ? litFill : stickCap))
        context.fill(inner, with: .radialGradient(
            Gradient(colors: [on ? litFill : keyBottom, on ? litFill.opacity(0.8) : keyTop]),
            center: CGPoint(x: c.x, y: c.y + radius * 0.2), startRadius: 0, endRadius: radius * 0.7))
        context.stroke(outer, with: .color(.white.opacity(0.1)), lineWidth: dp(0.75))
    }
}
