// The quit question on a TV, as SovEmu.Android's `QuitConfirm` (`QuitConfirm.kt`), at 1.5 points
// to the dp: a panel over the dimmed screen, starting on Stay so a press too many never quits,
// with Back closing it.
import SwiftUI

/// One Android TV dp (or sp) in tvOS points: Android lays the TV out 1280 dp wide, tvOS 1920.
private func dp(_ value: CGFloat) -> CGFloat { value * 1.5 }

/// Asks before leaving. It holds the focus while it is shown (nothing behind it can take it),
/// starts on Stay, and Back answers Stay.
struct TVQuitConfirm: View {
    var title = "Quit SovEmu?"
    let onStay: () -> Void
    let onQuit: () -> Void
    @FocusState private var stay: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(alignment: .leading, spacing: dp(20)) {
                Text(title).font(.system(size: dp(20), weight: .bold)).foregroundStyle(.white)
                HStack(spacing: dp(12)) {
                    Button("Stay", action: onStay).buttonStyle(TVMenuButtonStyle()).focused($stay)
                    Button("Quit", action: onQuit).buttonStyle(TVMenuButtonStyle(variant: .outline))
                }
            }
            .padding(dp(24))
            .frame(width: dp(420), alignment: .leading)
            .background(Sov.panel, in: RoundedRectangle(cornerRadius: dp(16)))
            .overlay(RoundedRectangle(cornerRadius: dp(16)).strokeBorder(Sov.edge, lineWidth: dp(1)))
            .focusSection()
        }
        .onExitCommand(perform: onStay)
        .defaultFocus($stay, true)
        .onAppear { stay = true }
    }
}
