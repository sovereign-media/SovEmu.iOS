// Where the iPhone and iPad app and the Apple TV app draw the same screen differently: the
// presentation the shared screens ask for by intent, and each platform's way of giving it.
// A TV has no navigation bar, no inspector and no touch: a panel slides in from the right over a
// dimmed screen and takes the focus, as SovEmu.Android's TV side panels do, and Menu closes it.
import SwiftUI

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

    /// The player's screen. On iOS, no status bar. On a TV, it holds the focus and swallows
    /// Back (a controller's B as much as the remote's), which would otherwise leave the app: the
    /// game reads controllers directly, and the remote's Back opens the in-game menu through
    /// `Controller`.
    @ViewBuilder func playerChrome() -> some View {
        #if os(tvOS)
        focusable()
            .onExitCommand {}
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

    /// A card that lifts when it has the focus on a TV; a plain button elsewhere.
    @ViewBuilder func cardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
/// The TV's side panel. Nothing behind it can take the focus while it is open (the screen behind
/// is disabled under a scrim), and Menu closes it, so the focus comes back to the card that
/// opened it.
private struct TVSidePanel<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel

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
        .animation(.easeOut(duration: 0.25), value: isPresented)
    }
}
#endif
