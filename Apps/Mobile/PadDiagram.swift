import SovEmuKit
import SwiftUI

/// A pad drawn from the server's layout (docs/CONTROLLERS.md, Systems and diagrams): `body`
/// shapes filled in one colour (tone 1 a darker recess), and each key a rounded rectangle with
/// its label centred. Keys in `highlighted` are lit. What is drawn is cropped to its bounding
/// box (`visibleBounds`, as the web client does) and scaled to fit, keeping its aspect.
struct PadDiagram: View {
    let layout: PadLayout
    var highlighted: Set<String> = []
    var accent: Color = Color(red: 0.36, green: 0.55, blue: 1)

    var body: some View {
        let bounds = layout.visibleBounds
        Canvas { context, size in
            let scale = min(size.width / bounds.w, size.height / bounds.h)
            let origin = CGPoint(
                x: (size.width - bounds.w * scale) / 2 - bounds.x * scale,
                y: (size.height - bounds.h * scale) / 2 - bounds.y * scale)
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
            }
            func path(_ r: CGRect, _ radius: Double) -> Path {
                Path(roundedRect: r, cornerRadius: min(radius * scale, min(r.width, r.height) / 2), style: .continuous)
            }
            for shape in layout.body {
                let fill = shape.tone == 1 ? Color(white: 0.13) : Color(white: 0.27)
                context.fill(path(rect(shape.x, shape.y, shape.w, shape.h), shape.r), with: .color(fill))
            }
            for key in layout.keys {
                let lit = highlighted.contains(key.key)
                let r = rect(key.x, key.y, key.w, key.h)
                let p = path(r, key.r)
                context.fill(p, with: .color(lit ? accent : Color(white: 0.42)))
                if lit { context.stroke(p, with: .color(.white), lineWidth: max(1, scale * 0.6)) }
                // Long labels ("Start", "Options") shrink to fit their key.
                let fontSize = min(r.height * 0.62, r.width / Double(max(1, key.label.count)) * 1.5)
                let text = Text(key.label).font(.system(size: max(5, fontSize), weight: .bold)).foregroundStyle(lit ? .white : Color(white: 0.92))
                context.draw(text, at: CGPoint(x: r.midX, y: r.midY))
            }
        }
        .aspectRatio(bounds.w / bounds.h, contentMode: .fit)
        .accessibilityLabel(layout.name)
    }
}

/// The device page's diagrams: the console's pad next to the player's controller, side by side
/// where they fit and stacked on a narrow screen. A keyboard has no diagram.
struct DiagramPair: View {
    let diagrams: GameMenu.Diagrams

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { panels }
            VStack(spacing: 8) { panels }
        }
    }

    @ViewBuilder private var panels: some View {
        if let system = diagrams.system {
            panel(system, diagrams.highlight.systemKeys)
        }
        if let controller = diagrams.controller {
            panel(controller, diagrams.highlight.controllerKeys)
        } else {
            Text("Keyboard: keys are listed by name.").font(.footnote).foregroundStyle(.secondary).frame(width: 200)
        }
    }

    private func panel(_ layout: PadLayout, _ lit: Set<String>) -> some View {
        VStack(spacing: 2) {
            // Cropped, a flat pad is shorter than a gamepad: the width is fixed, the height follows.
            let bounds = layout.visibleBounds
            PadDiagram(layout: layout, highlighted: lit).frame(width: 200, height: min(125, 200 * bounds.h / bounds.w))
            Text(layout.name).font(.caption).foregroundStyle(.secondary)
        }
    }
}
