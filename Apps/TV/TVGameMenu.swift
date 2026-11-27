// The in-game menu on a TV, as SovEmu.Android's (`Player.kt`: `InGameMenu`, `MenuItem`,
// `SlotItem`; `Cheats.kt`: `CheatsPage`), which its TV app draws on a 1280 dp screen: every size
// here is Android's, at 1.5 points to the dp. The rows and their navigation are the shared
// `GameMenu`'s; this only draws them.
import SovEmuKit
import SwiftUI

/// One Android TV dp (or sp) in tvOS points: Android lays the TV out 1280 dp wide, tvOS 1920.
private func dp(_ value: CGFloat) -> CGFloat { value * 1.5 }

/// Which kind of page the menu shows: each draws its rows its own way.
enum TVMenuStyle {
    case main, slots, disc, cheats
}

/// The menu's panel over the paused game: the system's badge and the page's title, then its
/// rows, the focused one filled with the accent. 360 dp wide on the main page, 480 on the others.
struct TVGameMenu: View {
    let title: String
    let system: SystemSummary
    let style: TVMenuStyle
    let items: [MenuItem]
    let focus: Int
    /// A line where the rows would be: loading, or no cheats yet.
    var note: String?
    /// The focused cheat's delete button has the focus, rather than its row.
    var deleteFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: dp(2)) {
            HStack(spacing: dp(8)) {
                TVSystemBadge(short: system.short, colour: system.accent)
                Text(title).font(.system(size: dp(16), weight: .bold)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(dp(8))
            if let note {
                Text(note).font(.system(size: dp(14))).foregroundStyle(Sov.slate400).padding(dp(12))
            }
            switch style {
            case .main, .disc: menuRows
            case .slots: slotRows
            case .cheats: cheatRows
            }
        }
        .padding(dp(12))
        .frame(width: style == .main ? dp(360) : dp(480), alignment: .leading)
        .background(Sov.panel, in: RoundedRectangle(cornerRadius: dp(16)))
        .overlay(RoundedRectangle(cornerRadius: dp(16)).strokeBorder(Sov.edge, lineWidth: dp(1)))
    }

    // MARK: - Main and disc

    @ViewBuilder private var menuRows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            // Quit sits under a rule, apart from the rest.
            if item.id == "quit" {
                Rectangle().fill(Sov.edge).frame(height: dp(1)).padding(.vertical, dp(4))
            }
            TVMenuRow(item: item, focused: index == focus)
        }
    }

    // MARK: - Save slots

    @ViewBuilder private var slotRows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            TVSlotRow(item: item, focused: index == focus)
        }
    }

    // MARK: - Cheats

    /// The cheats (each with its switch and a delete button beside it), then a rule, and adding
    /// one. A long list scrolls, the focused row kept in view (520 dp at most, as Android's).
    @ViewBuilder private var cheatRows: some View {
        let cheats = Array(items.enumerated()).filter { $0.element.isOn != nil }
        let add = items.firstIndex { $0.id == "add" }
        if !cheats.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: dp(4)) {
                        ForEach(cheats, id: \.element.id) { index, item in
                            TVCheatRow(item: item, focused: index == focus, deleteFocused: index == focus && deleteFocused)
                                .id(item.id)
                        }
                    }
                }
                .frame(height: min(CGFloat(cheats.count) * dp(60) - dp(4), dp(380)))
                .onChange(of: focus, initial: true) { _, new in
                    if items.indices.contains(new) { withAnimation { proxy.scrollTo(items[new].id, anchor: .center) } }
                }
            }
        }
        Rectangle().fill(Sov.edge).frame(height: dp(1)).padding(.vertical, dp(6))
        TVEyebrow(text: "Add a cheat").padding(.horizontal, dp(8))
        if let add {
            TVButtonLabel(title: items[add].title, symbol: "checkmark", focused: add == focus, large: false)
                .padding(.top, dp(4))
        }
    }
}

/// A row of the menu: its icon, its label and an optional second line; the accent at 45% when
/// focused.
private struct TVMenuRow: View {
    let item: MenuItem
    let focused: Bool

    var body: some View {
        HStack(spacing: dp(12)) {
            if let icon = item.icon {
                Image(systemName: icon).font(.system(size: dp(16)))
                    .foregroundStyle(focused ? .white : Sov.slate400)
                    .frame(width: dp(18), height: dp(18))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: dp(16))).foregroundStyle(.white).lineLimit(1)
                if let detail = item.detail {
                    Text(detail).font(.system(size: dp(12))).foregroundStyle(Sov.slate400)
                }
            }
            .padding(.vertical, item.detail == nil ? 0 : dp(6))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, dp(12))
        .frame(minHeight: dp(44))
        .background(focused ? Sov.accent.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: dp(10)))
        .opacity(item.enabled ? 1 : 0.4)
    }
}

/// A save slot: its screenshot (or a blank), its name and age; dimmed when it cannot be picked.
private struct TVSlotRow: View {
    let item: MenuItem
    let focused: Bool

    var body: some View {
        HStack(spacing: dp(14)) {
            ZStack {
                Color.black
                if let image = item.image, !image.isEmpty { RemoteImage(path: image, contentMode: .fit, pixelated: true) }
            }
            .frame(width: dp(56) * 4 / 3, height: dp(56))
            .clipShape(RoundedRectangle(cornerRadius: dp(6)))
            .overlay(RoundedRectangle(cornerRadius: dp(6)).strokeBorder(.white.opacity(0.1), lineWidth: dp(1)))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: dp(16), weight: .semibold)).foregroundStyle(.white)
                if let detail = item.detail {
                    Text(detail).font(.system(size: dp(13))).foregroundStyle(Sov.slate400)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, dp(10))
        .frame(height: dp(72))
        .background(focused ? Sov.accent.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: dp(10)))
        .opacity(item.enabled ? 1 : 0.4)
    }
}

/// A cheat: its name (or code), the code under it, and its switch; the delete button beside it
/// takes the focus with right, and gives it back with left.
private struct TVCheatRow: View {
    let item: MenuItem
    let focused: Bool
    let deleteFocused: Bool

    var body: some View {
        HStack(spacing: dp(6)) {
            HStack(spacing: dp(12)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.system(size: dp(15), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    if let detail = item.detail {
                        Text(detail).font(.system(size: dp(12), design: .monospaced)).foregroundStyle(Sov.slate400).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                TVSwitch(on: item.isOn ?? false)
            }
            .padding(.horizontal, dp(12))
            .frame(height: dp(56))
            .background(focused && !deleteFocused ? Sov.accent.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: dp(10)))
            Image(systemName: "xmark").font(.system(size: dp(16)))
                .foregroundStyle(deleteFocused ? .white : Sov.slate400)
                .frame(width: dp(44), height: dp(44))
                .background(deleteFocused ? Color(hex: 0xEF4444).opacity(0.33) : .white.opacity(0.06), in: Circle())
        }
    }
}

/// A switch's look (the row is what takes the press).
private struct TVSwitch: View {
    let on: Bool

    var body: some View {
        Circle().fill(.white).frame(width: dp(18), height: dp(18))
            .padding(dp(3))
            .frame(width: dp(44), height: dp(24), alignment: on ? .trailing : .leading)
            .background(on ? Sov.accent : .white.opacity(0.15), in: Capsule())
    }
}

// MARK: - The design system's pieces, at the TV's size

/// The system's coloured badge ("SNES"), as Android's `SystemBadge`.
struct TVSystemBadge: View {
    let short: String
    let colour: Color
    var large = false

    var body: some View {
        Text(short)
            .font(.system(size: dp(large ? 14 : 12), weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, dp(large ? 10 : 8)).padding(.vertical, dp(large ? 4 : 2))
            .background(colour, in: RoundedRectangle(cornerRadius: dp(large ? 8 : 6)))
    }
}

/// The uppercase label over a section, as Android's `Eyebrow`.
struct TVEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased()).font(.system(size: dp(12), weight: .semibold)).kerning(dp(1.2)).foregroundStyle(Sov.slate500)
    }
}

/// Android's `SovButton`, drawn for a row the menu's own focus drives: a rounded pill per role,
/// with a white ring outside it when focused (the space for the ring is always there).
struct TVButtonLabel: View {
    enum Variant { case primary, outline, glass }

    let title: String
    var symbol: String?
    var variant = Variant.primary
    var focused = false
    var large = true
    /// Fills its row, as Android's full-width buttons.
    var wide = true

    var body: some View {
        let fg: Color = variant == .outline ? Sov.slate200 : .white
        let bg: Color = switch variant {
        case .primary: Sov.accent
        case .outline: .clear
        case .glass: .white.opacity(focused ? 0.25 : 0.15)
        }
        HStack(spacing: dp(8)) {
            if let symbol { Image(systemName: symbol).font(.system(size: dp(15), weight: .semibold)) }
            Text(title).font(.system(size: dp(large ? 16 : 14), weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, dp(large ? 20 : 12))
        .frame(maxWidth: wide ? .infinity : nil)
        .frame(height: dp(large ? 44 : 36))
        .background(bg, in: RoundedRectangle(cornerRadius: dp(6)))
        .overlay {
            if variant == .outline { RoundedRectangle(cornerRadius: dp(6)).strokeBorder(Sov.edge, lineWidth: dp(1)) }
        }
        .padding(dp(3))
        .overlay {
            RoundedRectangle(cornerRadius: dp(9)).strokeBorder(.white.opacity(focused ? 0.7 : 0), lineWidth: dp(3))
        }
    }
}

/// `TVButtonLabel` for a real button, which tvOS's focus engine drives (the loading screen's
/// Continue / Start over, the quit question).
struct TVSovButtonStyle: ButtonStyle {
    var variant = TVButtonLabel.Variant.primary
    var symbol: String?

    func makeBody(configuration: Configuration) -> some View {
        TVSovButtonBody(configuration: configuration, variant: variant, symbol: symbol)
    }

    private struct TVSovButtonBody: View {
        let configuration: Configuration
        let variant: TVButtonLabel.Variant
        let symbol: String?
        @Environment(\.isFocused) private var focused

        var body: some View {
            let fg: Color = variant == .outline ? Sov.slate200 : .white
            let bg: Color = switch variant {
            case .primary: Sov.accent
            case .outline: .clear
            case .glass: .white.opacity(focused ? 0.25 : 0.15)
            }
            HStack(spacing: dp(8)) {
                if let symbol { Image(systemName: symbol).font(.system(size: dp(15), weight: .semibold)) }
                configuration.label.font(.system(size: dp(16), weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, dp(20))
            .frame(height: dp(44))
            .background(bg, in: RoundedRectangle(cornerRadius: dp(6)))
            .overlay {
                if variant == .outline { RoundedRectangle(cornerRadius: dp(6)).strokeBorder(Sov.edge, lineWidth: dp(1)) }
            }
            .padding(dp(3))
            .overlay {
                RoundedRectangle(cornerRadius: dp(9)).strokeBorder(.white.opacity(focused ? 0.7 : 0), lineWidth: dp(3))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}
