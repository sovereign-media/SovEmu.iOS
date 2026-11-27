// The Apple TV's controls for the system page, its game panel and drawers, ported from
// SovEmu.Android's design system (`:common:designsystem` Ui.kt, SidePanel.kt, FilterFields.kt):
// its buttons, chips, fields, dropdowns, side panel and drawers, at Android TV's sizes.
import SovEmuKit
import SwiftUI

/// Android's TV app lays its screens out 1280 dp wide (`SovTheme`: the web client at 150%); a
/// tvOS screen is 1920 points, so one Android dp or sp is 1.5 points.
enum TVScale {
    static let dp: CGFloat = 1.5
}


// MARK: - Buttons

/// SovEmu.Web's Button as Android's `SovButton` draws it on a TV: a rounded pill per role, with a
/// white ring outside it when focused (its space always kept, so focusing moves nothing).
struct TVSovButton: View {
    enum Variant { case primary, outline }

    let title: String
    let symbol: String?
    var variant: Variant = .primary
    var large = true
    var iconTint: Color?
    let action: () -> Void

    init(_ title: String, symbol: String? = nil, variant: Variant = .primary, large: Bool = true,
         iconTint: Color? = nil, action: @escaping () -> Void) {
        (self.title, self.symbol, self.variant, self.large, self.iconTint, self.action) =
            (title, symbol, variant, large, iconTint, action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8 * dp) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 16 * dp, weight: .semibold))
                        .foregroundStyle(iconTint ?? foreground)
                }
                Text(title).font(.system(size: (large ? 16 : 14) * dp, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(foreground)
            }
        }
        .buttonStyle(TVSovButtonStyle(variant: variant, large: large))
    }

    private var foreground: Color { variant == .primary ? .white : Sov.slate200 }
}

private struct TVSovButtonStyle: ButtonStyle {
    let variant: TVSovButton.Variant
    let large: Bool

    func makeBody(configuration: Configuration) -> some View {
        TVSovButtonBody(label: configuration.label, variant: variant, large: large, pressed: configuration.isPressed)
    }
}

private struct TVSovButtonBody<Label: View>: View {
    let label: Label
    let variant: TVSovButton.Variant
    let large: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .padding(.horizontal, (large ? 20 : 12) * dp)
            .frame(height: (large ? 44 : 36) * dp)
            .background(variant == .primary ? Sov.accent : .clear, in: RoundedRectangle(cornerRadius: 6 * dp))
            .overlay {
                if variant == .outline { RoundedRectangle(cornerRadius: 6 * dp).strokeBorder(Sov.edge, lineWidth: 1 * dp) }
            }
            .opacity(enabled ? (pressed ? 0.8 : 1) : 0.4)
            .padding(3 * dp)
            .overlay {
                if focused { RoundedRectangle(cornerRadius: 9 * dp).strokeBorder(.white.opacity(0.7), lineWidth: 3 * dp) }
            }
    }
}

// MARK: - Chips

/// A capsule toolbar of chips (Android's `ChipStrip`, the web's TabStrip).
struct TVChipStrip<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 2 * dp) { content() }
            .padding(4 * dp)
            .background(Sov.surface.opacity(0.9), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1 * dp))
    }
}

/// The strip's divider.
struct TVChipDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.1)).frame(width: 1 * dp, height: 20 * dp).padding(.horizontal, 4 * dp)
    }
}

/// A chip: quiet at rest, filled when its action is in effect (`on`), ringed when focused.
struct TVChip: View {
    let title: String
    let symbol: String
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * dp) {
                Image(systemName: symbol).font(.system(size: 13 * dp))
                Text(title).font(.system(size: 14 * dp, weight: on ? .semibold : .regular)).lineLimit(1)
            }
        }
        .buttonStyle(TVChipStyle(on: on))
    }
}

private struct TVChipStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        TVChipBody(label: configuration.label, on: on)
    }
}

private struct TVChipBody<Label: View>: View {
    let label: Label
    let on: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .foregroundStyle(on || focused ? .white : Sov.slate400)
            .padding(.horizontal, 14 * dp)
            .frame(height: 32 * dp)
            .background(on ? Color.white.opacity(0.15) : focused ? .white.opacity(0.1) : .clear, in: Capsule())
            .overlay { if focused { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 2 * dp) } }
            .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Dropdowns and fields

/// One choice in a dropdown, with how many games have it when that helps.
struct TVOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var count: Int?

    var id: Value { value }
}

/// A dropdown menu, as Android's `DropdownMenu` in the panel's colour: rows with a tick on what is
/// picked. It takes the focus when it opens, and Menu closes it.
struct TVDropdown<Value: Hashable>: View {
    let options: [TVOption<Value>]
    let isOn: (Value) -> Bool
    var minWidth: CGFloat = 112 * dp
    /// A "Clear" row at the end, when something is picked in a multi-select.
    var onClear: (() -> Void)?
    let onPick: (Value) -> Void
    let onClose: () -> Void
    @FocusState private var focus: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                    Button { onPick(option.value) } label: {
                        row(option.label, count: option.count, symbol: isOn(option.value) ? "checkmark" : nil,
                            colour: Sov.slate200)
                    }
                    .buttonStyle(TVMenuRowStyle())
                    .focused($focus, equals: i)
                }
                if let onClear {
                    Button(action: onClear) { row("Clear", count: nil, symbol: "xmark", colour: Sov.slate400) }
                        .buttonStyle(TVMenuRowStyle())
                        .focused($focus, equals: -1)
                }
            }
            .padding(.vertical, 8 * dp)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        // A fixed height: as an overlay it would be offered only the size of the field it opens from.
        .frame(height: min(CGFloat(options.count + (onClear == nil ? 0 : 1)) * 40 * dp + 16 * dp, 420 * dp))
        .fixedSize()
        .background(Sov.panel, in: RoundedRectangle(cornerRadius: 12 * dp))
        .overlay(RoundedRectangle(cornerRadius: 12 * dp).strokeBorder(Sov.edge, lineWidth: 1 * dp))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        .focusSection()
        .onExitCommand(perform: onClose)
        .onAppear {
            let first = options.firstIndex { isOn($0.value) } ?? 0
            DispatchQueue.main.async { focus = first }
        }
    }

    private func row(_ label: String, count: Int?, symbol: String?, colour: Color) -> some View {
        HStack(spacing: 12 * dp) {
            ZStack { if let symbol { Image(systemName: symbol).font(.system(size: 12 * dp, weight: .bold)) } }
                .frame(width: 14 * dp)
            Text(label).font(.system(size: 14 * dp)).lineLimit(1)
            Spacer(minLength: 0)
            if let count { Text("\(count)").font(.system(size: 12 * dp)).foregroundStyle(Sov.slate500).padding(.leading, 8 * dp) }
        }
        .foregroundStyle(colour)
        .padding(.horizontal, 12 * dp)
        .frame(height: 40 * dp)
    }
}

private struct TVMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TVMenuRow(label: configuration.label) }
}

private struct TVMenuRow<Label: View>: View {
    let label: Label
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .background(focused ? Color.white.opacity(0.12) : .clear)
            .contentShape(Rectangle())
    }
}

/// A filter's field (Android's `Field`): its label above a box showing what is picked, which
/// opens a dropdown under it.
struct TVFieldBox: View {
    let label: String
    let summary: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * dp) {
            TVEyebrow(label)
            Button(action: action) {
                HStack(spacing: 8 * dp) {
                    Text(summary).font(.system(size: 14 * dp)).lineLimit(1)
                        .foregroundStyle(summary == "Any" ? Sov.slate400 : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 13 * dp, weight: .semibold)).foregroundStyle(Sov.slate400)
                }
            }
            .buttonStyle(TVBoxStyle())
            .accessibilityLabel("\(label): \(summary)")
        }
    }
}

/// The box a field or a text field draws: faint at rest, brighter with a white edge when focused.
struct TVBoxStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TVBox(label: configuration.label) }
}

private struct TVBox<Label: View>: View {
    let label: Label
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .padding(.horizontal, 12 * dp)
            .frame(maxWidth: .infinity, minHeight: 40 * dp, alignment: .leading)
            .background(.white.opacity(focused ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8 * dp))
            .overlay(RoundedRectangle(cornerRadius: 8 * dp)
                .strokeBorder(.white.opacity(focused ? 0.6 : 0.15), lineWidth: (focused ? 2 : 1) * dp))
    }
}

/// A text field for a TV, as Android's `TvTextField`: the remote passes over it like any other
/// control, and select opens tvOS's keyboard to type into it. tvOS draws the field itself (its
/// platter cannot be replaced), so it does not have Android's bordered box.
struct TVTextBox: View {
    let label: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15 * dp))
            .foregroundStyle(Sov.slate100)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(onSubmit)
    }
}

/// A toggle row (the collections drawer's): a check box and its label, as Android's `Toggle`.
struct TVToggleRow: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * dp) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4 * dp).fill(on ? Sov.accent : .clear)
                    RoundedRectangle(cornerRadius: 4 * dp).strokeBorder(on ? Sov.accent : Sov.slate500, lineWidth: 1.5 * dp)
                    if on { Image(systemName: "checkmark").font(.system(size: 11 * dp, weight: .bold)).foregroundStyle(.white) }
                }
                .frame(width: 18 * dp, height: 18 * dp)
                Text(title).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate200).lineLimit(1)
            }
        }
        .buttonStyle(TVBoxStyle())
    }
}

// MARK: - Text

/// The uppercase label over a section ("SAVES", "GENRE").
struct TVEyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.system(size: 12 * dp, weight: .semibold)).kerning(1.2 * dp).foregroundStyle(Sov.slate500)
    }
}

/// A line of a panel's facts: an icon and its text.
struct TVFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6 * dp) {
            Image(systemName: symbol).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate500).frame(width: 16 * dp)
            Text(text).font(.system(size: 14 * dp)).foregroundStyle(Sov.slate300)
        }
    }
}

/// The system's coloured badge ("NES"), at TV size.
struct TVSystemBadge: View {
    let short: String
    let colour: Color
    var large = false

    var body: some View {
        Text(short)
            .font(.system(size: (large ? 14 : 12) * dp, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, (large ? 10 : 8) * dp).padding(.vertical, (large ? 4 : 2) * dp)
            .background(colour, in: RoundedRectangle(cornerRadius: (large ? 8 : 6) * dp))
    }
}

// MARK: - Panels and drawers

/// A panel's close mark over its picture's top-right corner. Not focusable: Menu closes a panel on
/// a TV, as Back does on Android's (its `PanelClose` cannot take the focus).
struct TVPanelClose: View {
    var body: some View {
        Image(systemName: "xmark").font(.system(size: 15 * dp, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 36 * dp, height: 36 * dp)
            .background(.black.opacity(0.5), in: Circle())
            .padding(12 * dp)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A dropdown hanging from this view's bottom-left corner, `gap` below it, over what follows
    /// (give this view's container a higher `zIndex` while it shows).
    func dropdownBelow<Menu: View>(gap: CGFloat = 4 * TVScale.dp, @ViewBuilder _ menu: () -> Menu) -> some View {
        overlay(alignment: .bottomLeading) {
            Color.clear.frame(height: 0)
                .overlay(alignment: .topLeading) { menu().padding(.top, gap) }
        }
    }

    /// Android's `SidePanel` on a TV: 448 dp on the right edge, the full height of the screen, on
    /// the page's colour with a faint edge. Menu closes it.
    func tvSidePanelChrome(onClose: @escaping () -> Void) -> some View {
        frame(width: 448 * dp)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Sov.surface.opacity(0.96))
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.1)).frame(width: 1 * dp) }
            .focusSection()
            .onExitCommand(perform: onClose)
    }

    /// Android's drawers (filters, collections): 384 dp from the right edge, the full height.
    func tvDrawerChrome(onClose: @escaping () -> Void) -> some View {
        frame(width: 384 * dp)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Sov.surface.opacity(0.97))
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.1)).frame(width: 1 * dp) }
            .focusSection()
            .onExitCommand(perform: onClose)
    }
}

/// A drawer's title row and the rule under it: its icon, title, a count pill and a close mark.
struct TVDrawerHeader: View {
    let symbol: String
    let title: String
    var count: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12 * dp) {
                Image(systemName: symbol).font(.system(size: 18 * dp)).foregroundStyle(.white)
                Text(title).font(.system(size: 18 * dp, weight: .semibold)).foregroundStyle(.white)
                if count > 0 {
                    Text("\(count) on").font(.system(size: 12 * dp, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10 * dp).padding(.vertical, 2 * dp)
                        .background(Sov.accent, in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "xmark").font(.system(size: 16 * dp)).foregroundStyle(Sov.slate400)
                    .frame(width: 36 * dp, height: 36 * dp)
            }
            .padding(.horizontal, 20 * dp).padding(.top, 20 * dp).padding(.bottom, 16 * dp)
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1 * dp).padding(.horizontal, 20 * dp)
        }
    }
}
