// Where the iPhone and iPad app and the Apple TV app draw the same screen differently: the
// presentation the shared screens ask for by intent, and each platform's way of giving it.
// A TV has no navigation bar, no inspector and no touch: a panel slides in from the right over a
// dimmed screen and takes the focus, as SovEmu.Android's TV side panels do, and Menu closes it.
import SwiftUI

/// A size for a phone or tablet, or a TV's (seen from across a room, at 1920 points wide).
func onTV(_ value: CGFloat, tv: CGFloat) -> CGFloat {
    #if os(tvOS)
    tv
    #else
    value
    #endif
}

extension View {
    /// A page title kept small: inline in the navigation bar on iOS; tvOS has no bar to put it in.
    @ViewBuilder func inlineTitle() -> some View {
        #if os(tvOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// A list drawn on the screen's own background rather than the system's grouped one.
    @ViewBuilder func plainListBackground() -> some View {
        #if os(tvOS)
        self
        #else
        scrollContentBackground(.hidden)
        #endif
    }

    /// The search field: always showing under the title on iOS; tvOS's own search screen, with
    /// its keyboard, on a TV.
    @ViewBuilder func searchField(_ text: Binding<String>, prompt: String) -> some View {
        #if os(tvOS)
        searchable(text: text, prompt: prompt)
        #else
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }

    /// A game's panel beside the page: an inspector on iOS (a sheet on an iPhone); on a TV, a
    /// panel over the right of the screen that keeps the focus until Menu closes it.
    @ViewBuilder func sidePanel<Panel: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        #if os(tvOS)
        modifier(TVSidePanel(isPresented: isPresented, panel: panel))
        #else
        inspector(isPresented: isPresented) {
            panel()
                .inspectorColumnWidth(min: 360, ideal: 420, max: 480)
                .presentationDetents([.medium, .large])
                .presentationBackground(Sov.surface)
        }
        #endif
    }

    /// The player's screen: no status bar on iOS; on a TV it holds the focus, so the remote's
    /// commands reach the player (which handles them).
    @ViewBuilder func playerChrome() -> some View {
        #if os(tvOS)
        focusable()
        #else
        statusBarHidden()
        #endif
    }

    /// A text field with a border on iOS; tvOS draws its own fields.
    @ViewBuilder func roundedField() -> some View {
        #if os(tvOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }

    /// A game's or a system's card. On a TV the focused card grows, with a shadow and an accent
    /// ring, and its caption keeps its colours (tvOS's `.plain` and `.card` styles put a white
    /// platter behind the whole label, and `.borderless` lifts only images, which a card
    /// without artwork has none of); a plain button elsewhere.
    @ViewBuilder func cardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(TVCardStyle())
        #else
        buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
private struct TVCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVCard(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct TVCard<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .padding(6)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Sov.accent, lineWidth: focused ? 4 : 0)
            }
            .scaleEffect(pressed ? 1.02 : focused ? 1.08 : 1)
            .shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 20, y: 12)
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// The TV's side panel. Nothing behind it can take the focus while it is open (the screen behind
/// is disabled under a scrim), and Menu closes it, so the focus comes back to the card that
/// opened it.
private struct TVSidePanel<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel
    @Namespace private var scope
    @Environment(\.resetFocus) private var resetFocus

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content
                .disabled(isPresented)
            if isPresented {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                panel()
                    .frame(width: 760)
                    .frame(maxHeight: .infinity)
                    .background(Sov.surface.ignoresSafeArea())
                    .focusSection()
                    .onExitCommand { isPresented = false }
                    .transition(.move(edge: .trailing))
            }
        }
        .focusScope(scope)
        // A disabled view keeps the focus it had: hand it to the panel once it is there, and back
        // to the page (the focus engine's choice) when it closes.
        .onChange(of: isPresented) { _, _ in
            DispatchQueue.main.async { resetFocus(in: scope) }
        }
        .animation(.easeOut(duration: 0.25), value: isPresented)
    }
}
#endif
