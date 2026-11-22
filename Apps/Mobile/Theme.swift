import SovEmuKit
import SwiftUI

/// SovEmu.Web's theme (src/styles/global.css) and Tailwind's slate greys, as the Android app's `Sov`.
enum Sov {
    static let surface = Color(hex: 0x0B0D12)
    static let panel = Color(hex: 0x151922)
    static let edge = Color(hex: 0x2A3142)
    static let accent = Color(hex: 0x4169E1)
    static let slate100 = Color(hex: 0xF1F5F9)
    static let slate200 = Color(hex: 0xE2E8F0)
    static let slate300 = Color(hex: 0xCBD5E1)
    static let slate400 = Color(hex: 0x94A3B8)
    static let slate500 = Color(hex: 0x64748B)
    static let slate950 = Color(hex: 0x020617)
    static let red300 = Color(hex: 0xFCA5A5)
    static let amber200 = Color(hex: 0xFDE68A)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// `linear-gradient(145deg, c, color-mix(c [mix]%, black))`, the web's card fill.
func tile(_ c: Color, mix: Double = 0.3) -> LinearGradient {
    LinearGradient(colors: [c, c.mix(with: .black, by: 1 - mix)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The system's coloured badge ("SNES").
struct SystemBadge: View {
    let short: String
    let colour: Color
    var large = false

    var body: some View {
        Text(short)
            .font(.system(size: large ? 14 : 12, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 10 : 8).padding(.vertical, large ? 4 : 2)
            .background(colour, in: RoundedRectangle(cornerRadius: large ? 8 : 6))
    }
}

/// A row's title with its icon ("Continue playing").
struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Sov.slate400)
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(1)
        }
    }
}

/// The uppercase label over a section ("SAVES", "GENRE").
struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).kerning(1.2).foregroundStyle(Sov.slate500)
    }
}

/// A card's detail line with the game's release label (what tells it from same-titled games on
/// its system: "Translation", "Rev 1") in amber, before the rest (`first`) or after it.
func releaseLine(_ release: String?, _ line: String, first: Bool) -> Text {
    guard let release else { return Text(line) }
    let label = Text(release).foregroundStyle(Sov.amber200).fontWeight(.medium)
    return first ? Text("\(label) · \(line)") : Text("\(line) · \(label)")
}

/// SovEmu.Web's Button: a rounded pill per role.
struct SovButtonStyle: ButtonStyle {
    enum Variant { case primary, outline, light, glass }
    var variant: Variant = .primary
    var large = true

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = switch variant {
        case .primary: (Sov.accent, .white)
        case .outline: (.clear, Sov.slate200)
        case .light: (.white, Sov.slate950)
        case .glass: (.white.opacity(0.15), .white)
        }
        configuration.label
            .font(.system(size: large ? 16 : 14, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, large ? 20 : 12)
            .frame(height: large ? 44 : 36)
            .background(bg, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if variant == .outline { RoundedRectangle(cornerRadius: 6).stroke(Sov.edge, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == SovButtonStyle {
    static func sov(_ variant: SovButtonStyle.Variant = .primary, large: Bool = true) -> SovButtonStyle {
        SovButtonStyle(variant: variant, large: large)
    }
}

/// A chip of the system page's toolbar: quiet at rest, filled when its action is in effect.
struct ChipLabel: View {
    let title: String
    let symbol: String
    var on = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(title).font(.system(size: 14, weight: on ? .semibold : .regular)).lineLimit(1)
        }
        .foregroundStyle(on ? .white : Sov.slate300)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(on ? Color.white.opacity(0.15) : .clear, in: Capsule())
    }
}

/// A toggle pill (the filter sheet's): accent when on.
struct TogglePill<Label: View>: View {
    let on: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                label()
            }
            .font(.system(size: 14))
            .foregroundStyle(on ? .white : Sov.slate200)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(on ? Sov.accent : .clear, in: Capsule())
            .overlay { if !on { Capsule().stroke(.white.opacity(0.15), lineWidth: 1) } }
        }
        .buttonStyle(.plain)
    }
}

/// A line of the game panel's facts: an icon and its text.
struct Fact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Sov.slate500)
            Text(text).font(.system(size: 14)).foregroundStyle(Sov.slate300)
        }
    }
}

/// The symbol for what a multi-part game's files are: a disc, a floppy, a cassette or a stack.
func partSymbol(_ kind: PartKind?) -> String {
    switch kind {
    case .disk, .side: "opticaldiscdrive"
    case .tape: "recordingtape"
    case .part: "square.stack"
    default: "opticaldisc"
    }
}

/// CRT scan lines: a dark line every three points, drawn over the menus (never over a game).
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                y += 3
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Up to two initials for an account's avatar: "Bruce Lee" → "BL", "mum" → "M".
func initials(_ name: String) -> String {
    let parts = name.split(whereSeparator: { " ._-".contains($0) })
    let letters = parts.count > 1 ? "\(parts[0].prefix(1))\(parts[1].prefix(1))" : String((parts.first ?? "?").prefix(1))
    return letters.uppercased()
}
