// Home's "Continue playing" panel on the Apple TV, as SovEmu.Android's `ContinuePanel`
// (`:common:feature` ContinuePanel.kt) on its TV app. The iPhone and iPad draw theirs in
// Apps/Shared/ContinuePanel.swift; this takes the same arguments.
import SovEmuKit
import SwiftUI


/// Where the player left off (the auto save's screenshot), when, and Continue, which takes the
/// focus; Game details goes on to the game's own panel on its system's page (Start over, the other
/// saves, the description). Menu closes it.
///
/// Drawn as a whole side panel (448 dp on the right, full height): put it over the page, beside a
/// dimmed screen, with `tvContinuePanel` (or Platform.swift's `sidePanel`, which draws the scrim).
struct TVContinuePanel: View {
    let game: Game
    let system: SystemSummary?
    let onPlay: (Start) -> Void
    let onDetails: () -> Void
    let onClose: () -> Void
    @FocusState private var first: Bool

    var body: some View {
        let short = system?.short ?? game.system.uppercased()
        let now = Int64(Date().timeIntervalSince1970)
        VStack(spacing: 0) {
            leftOff(short: short).overlay(alignment: .topTrailing) { TVPanelClose() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16 * dp) {
                    VStack(alignment: .leading, spacing: 0) {
                        TVSystemBadge(short: short, colour: system?.accent ?? Sov.accent)
                        Text(game.title).font(.system(size: 24 * dp, weight: .black)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10 * dp)
                        if let release = game.release {
                            Text(release).font(.system(size: 14 * dp, weight: .medium)).foregroundStyle(Sov.amber200)
                                .padding(.top, 4 * dp)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6 * dp) {
                        if let save = game.autoSave {
                            TVFact(symbol: "square.and.arrow.down", text: "Saved \(formatAgo(Int64(save.savedAt), now: now))")
                        }
                        if game.playCount > 0 {
                            TVFact(symbol: "clock.arrow.circlepath",
                                   text: "Played \(game.playCount)× · last \(formatAgo(GameIndex.playedAt(game.lastPlayedAt), now: now))")
                        }
                    }
                    HStack(spacing: 8 * dp) {
                        // A game played without an auto save (it never got one) has nothing to continue.
                        if game.autoSave != nil {
                            TVSovButton("Continue", symbol: "play.fill") { onPlay(.continue) }.focused($first)
                        } else {
                            TVSovButton("Play", symbol: "play.fill") { onPlay(.new) }.focused($first)
                        }
                        TVSovButton("Game details", symbol: "info.circle", variant: .outline, action: onDetails)
                    }
                }
                .padding(.horizontal, 24 * dp).padding(.top, 16 * dp).padding(.bottom, 24 * dp)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tvSidePanelChrome(onClose: onClose)
        .onAppear { DispatchQueue.main.async { first = true } }
        .onChange(of: game.id) { DispatchQueue.main.async { first = true } }
    }

    /// The auto save's screenshot, whole (letterboxed in a 16:9 frame) and on black like a TV; the
    /// game's artwork if there is none.
    private func leftOff(short: String) -> some View {
        ZStack {
            Color.black
            if let shot = game.autoSave?.screenshotUrl {
                RemoteImage(path: shot, contentMode: .fit, pixelated: true)
            } else {
                Rectangle().fill(tile(system?.accent ?? Sov.accent))
                Text(short).font(.system(size: 60 * dp, weight: .black)).foregroundStyle(.white.opacity(0.8))
                RemoteImage(path: game.image ?? game.cover ?? game.thumb, contentMode: game.image != nil ? .fill : .fit)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }
}

extension View {
    /// Home's Continue panel over the page while `game` is set: the screen dimmed behind it, the
    /// panel sliding in from the right with the focus (the page behind cannot take it), and Menu
    /// closing it (`onClose` should send the focus back to the card that opened it).
    func tvContinuePanel(
        game: Game?, system: SystemSummary?, onPlay: @escaping (Start) -> Void, onDetails: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        disabled(game != nil)
            .overlay(alignment: .trailing) {
                // Over the whole screen, past the safe area, as Android's panel reaches the edges.
                ZStack(alignment: .trailing) {
                    if let game {
                        Color.black.opacity(0.6).transition(.opacity)
                        TVContinuePanel(game: game, system: system, onPlay: onPlay, onDetails: onDetails, onClose: onClose)
                            .transition(.move(edge: .trailing))
                    }
                }
                .ignoresSafeArea()
            }
            .animation(.easeOut(duration: 0.25), value: game?.id)
    }
}
