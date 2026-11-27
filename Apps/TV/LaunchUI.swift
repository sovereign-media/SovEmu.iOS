// The pieces the TV's launch screens and Search are drawn with, as SovEmu.Android's design
// system draws them on a TV (`Ui.kt`: `SovButton`, `Toggle`, `FocusCard`; `Brand.kt`;
// `LaunchCommon.kt`: `LaunchBackdrop`, `ErrorLine`; `Login.kt`'s `Field`). Every size is
// Android's dp times `launchDp`.
import SwiftUI


/// Android's `Sov.Muted`.
let launchMuted = Color(hex: 0x8B93A7)

/// The signed-out screens' backdrop: a deep blue fading to the surface, the content centred.
struct LaunchBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1E2A4A), Sov.surface], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0, content: content)
                .padding(24 * launchDp)
        }
    }
}

/// The sign-in form's card: the panel, a hairline edge, rounded.
struct LaunchCard<Content: View>: View {
    var width: CGFloat = 384
    var spacing: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing * launchDp, content: content)
            .padding(32 * launchDp)
            .frame(width: width * launchDp, alignment: .leading)
            .background(Sov.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: 16 * launchDp))
            .overlay(RoundedRectangle(cornerRadius: 16 * launchDp).stroke(Sov.edge, lineWidth: launchDp))
    }
}

/// SovEmu's name with its mark, the mark a little taller than the text (`size` in sp).
struct LaunchBrand: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 8 * launchDp) {
            Image("SovEmuMark").resizable().scaledToFit().frame(height: size * 1.5 * launchDp).foregroundStyle(Sov.accent)
            Text("Sov").foregroundStyle(.white) + Text(" ") + Text("Emu").foregroundStyle(Sov.accent)
        }
        .font(.system(size: size * launchDp, weight: .black))
    }
}

/// A failure, in the sign-in form's red.
struct LaunchErrorLine: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        HStack(spacing: 8 * launchDp) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 16 * launchDp))
            Text(message).font(.system(size: 14 * launchDp))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Sov.red300)
        .padding(.horizontal, 12 * launchDp).padding(.vertical, 8 * launchDp)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xEF4444).opacity(0.15), in: RoundedRectangle(cornerRadius: 6 * launchDp))
    }
}

// MARK: - Buttons

/// SovEmu.Web's Button as Android's TV draws it: a rounded pill per role, and focus a white ring
/// just outside it (the room for the ring is always there, so focusing moves nothing).
struct LaunchButtonStyle: ButtonStyle {
    enum Variant { case primary, outline, ghost }
    var variant: Variant = .primary
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        LaunchButtonBody(configuration: configuration, variant: variant, fill: fill)
    }
}

private struct LaunchButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: LaunchButtonStyle.Variant
    let fill: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let (bg, fg): (Color, Color) = switch variant {
        case .primary: (Sov.accent, .white)
        case .outline: (.clear, Sov.slate200)
        case .ghost: (focused ? .white.opacity(0.1) : .clear, Sov.slate400)
        }
        configuration.label
            .font(.system(size: 16 * launchDp, weight: .semibold))
            .labelStyle(LaunchLabelStyle())
            .lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, 20 * launchDp)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 44 * launchDp)
            .background(bg, in: RoundedRectangle(cornerRadius: 6 * launchDp))
            .overlay {
                if variant == .outline { RoundedRectangle(cornerRadius: 6 * launchDp).stroke(Sov.edge, lineWidth: launchDp) }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .padding(3 * launchDp)
            .overlay {
                if focused { RoundedRectangle(cornerRadius: 9 * launchDp).stroke(.white.opacity(0.7), lineWidth: 3 * launchDp) }
            }
    }
}

/// An icon (18 launchDp) and its words, 8 launchDp apart.
private struct LaunchLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8 * launchDp) {
            configuration.icon.font(.system(size: 18 * launchDp, weight: .regular))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == LaunchButtonStyle {
    static func launch(_ variant: LaunchButtonStyle.Variant = .primary, fill: Bool = false) -> LaunchButtonStyle {
        LaunchButtonStyle(variant: variant, fill: fill)
    }
}

/// A toggle pill (*Secure connections only*): accent with a check when on, an outline when off,
/// a brighter outline with the focus.
struct LaunchToggle: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }.buttonStyle(ToggleStyle(on: on))
    }

    private struct ToggleStyle: ButtonStyle {
        let on: Bool
        func makeBody(configuration: Configuration) -> some View { Drawn(configuration: configuration, on: on) }
    }

    private struct Drawn: View {
        let configuration: ButtonStyleConfiguration
        let on: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            HStack(spacing: 6 * launchDp) {
                if on { Image(systemName: "checkmark").font(.system(size: 14 * launchDp, weight: .semibold)) }
                configuration.label.font(.system(size: 14 * launchDp)).padding(.horizontal, 4 * launchDp)
            }
            .foregroundStyle(on ? .white : Sov.slate200)
            .padding(.horizontal, 12 * launchDp)
            .frame(height: 32 * launchDp)
            .background(on ? Sov.accent : focused ? .white.opacity(0.1) : .clear, in: Capsule())
            .overlay {
                if focused || !on {
                    Capsule().stroke(.white.opacity(focused ? 0.6 : 0.15), lineWidth: (focused ? 2 : 1) * launchDp)
                }
            }
        }
    }
}

/// A focusable card (an account's tile, a server's row): what it draws grows a little and gets a
/// white ring with the focus; its frame does not move.
struct LaunchCardStyle: ButtonStyle {
    var corner: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View { Drawn(configuration: configuration, corner: corner) }

    private struct Drawn: View {
        let configuration: ButtonStyleConfiguration
        let corner: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: corner * launchDp))
                .overlay {
                    if focused { RoundedRectangle(cornerRadius: corner * launchDp).stroke(.white.opacity(0.8), lineWidth: 4 * launchDp) }
                }
                .scaleEffect(focused ? 1.05 : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

// MARK: - Fields

/// Which field a page puts the focus on first.
enum LaunchFocus: Hashable {
    case server, username, password, name, value, search
}

/// A labelled input, as Android's TV `Field`: Select opens tvOS's keyboard. The box is the
/// web's input (dark, a hairline edge), with a light ring while it has the focus.
struct LaunchField: View {
    let label: String
    @Binding var text: String
    var secret = false
    var content: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var focus: FocusState<LaunchFocus?>.Binding?
    var tag: LaunchFocus?

    init(
        _ label: String, text: Binding<String>, secret: Bool = false, content: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default, focus: FocusState<LaunchFocus?>.Binding? = nil, tag: LaunchFocus? = nil
    ) {
        self.label = label
        _text = text
        self.secret = secret
        self.content = content
        self.keyboard = keyboard
        self.focus = focus
        self.tag = tag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * launchDp) {
            Text(label).font(.system(size: 14 * launchDp)).foregroundStyle(Sov.slate200)
            LaunchInput(placeholder: label, text: $text, secret: secret, content: content, keyboard: keyboard, focus: focus, tag: tag)
        }
    }
}

/// The input box alone (Search's field has no label over it). It is drawn here rather than by
/// tvOS's `TextField`, whose focused platter (a white capsule) hides what is typed: the box is a
/// button, and Select opens tvOS's keyboard on a hidden `UITextField` that holds the text.
struct LaunchInput: View {
    let placeholder: String
    @Binding var text: String
    var secret = false
    var content: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var onSubmit: () -> Void = {}
    var focus: FocusState<LaunchFocus?>.Binding?
    var tag: LaunchFocus?
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            Group {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(Sov.slate500)
                } else {
                    Text(secret ? String(repeating: "•", count: text.count) : text).foregroundStyle(.white)
                }
            }
            .font(.system(size: 16 * launchDp))
            .lineLimit(1)
            .truncationMode(.head)
        }
        .buttonStyle(InputStyle())
        .focusTag(focus, tag)
        .background {
            KeyboardField(
                text: $text, editing: $editing, secret: secret, placeholder: placeholder, content: content,
                keyboard: keyboard, onSubmit: onSubmit)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(placeholder)
        .accessibilityValue(secret ? "" : text)
    }

    private struct InputStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Drawn(configuration: configuration) }
    }

    private struct Drawn: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 12 * launchDp)
                .frame(maxWidth: .infinity, minHeight: 40 * launchDp, alignment: .leading)
                .background(Color(hex: 0x0A0B0F), in: RoundedRectangle(cornerRadius: 6 * launchDp))
                .overlay {
                    RoundedRectangle(cornerRadius: 6 * launchDp)
                        .stroke(focused ? Color.white.opacity(0.7) : Sov.edge, lineWidth: (focused ? 2 : 1) * launchDp)
                }
        }
    }
}

/// The `UITextField` that tvOS's keyboard types into: never focusable itself, it becomes the
/// first responder (which opens the keyboard) when `editing` turns on, and turns it off when the
/// keyboard closes.
private struct KeyboardField: UIViewRepresentable {
    @Binding var text: String
    @Binding var editing: Bool
    let secret: Bool
    let placeholder: String
    let content: UITextContentType?
    let keyboard: UIKeyboardType
    let onSubmit: () -> Void

    final class Field: UITextField {
        override var canBecomeFocused: Bool { false }
    }

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.notified(_:)), name: UITextField.textDidChangeNotification,
            object: field)
        return field
    }

    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.isSecureTextEntry = secret
        field.placeholder = placeholder
        field.textContentType = content
        field.keyboardType = keyboard
        if field.text != text { field.text = text }
        if editing && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: KeyboardField

        init(_ parent: KeyboardField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        @objc func notified(_ note: Notification) {
            if let field = note.object as? UITextField { changed(field) }
        }

        /// Menu closes tvOS's keyboard as a cancel, putting the field's old text back: what was
        /// typed is kept anyway (taken as it changed), as Back keeps it on Android's TV.
        func textFieldDidEndEditing(_ field: UITextField) {
            parent.editing = false
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit()
            return true
        }
    }
}

extension View {
    /// `focused(_:equals:)` when there is a binding to report to.
    @ViewBuilder func focusTag(_ focus: FocusState<LaunchFocus?>.Binding?, _ tag: LaunchFocus?) -> some View {
        if let focus, let tag { focused(focus, equals: tag) } else { self }
    }
}
