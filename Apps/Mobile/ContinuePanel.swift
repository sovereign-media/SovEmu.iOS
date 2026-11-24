import SovEmuKit
import SwiftUI

/// Home's panel for a game in "Continue playing", as the other clients': where the player left
/// off (the auto save's screenshot), when, and Continue; Game details goes on to the game's own
/// panel on its system's page (Start over, the other saves, the description).
struct ContinuePanel: View {
    let game: Game
    let system: SystemSummary?
    let onPlay: (Start) -> Void
    let onDetails: () -> Void
    let onClose: () -> Void

    var body: some View {
        let short = system?.short ?? game.system.uppercased()
        let now = Int64(Date().timeIntervalSince1970)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                leftOff(short: short)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SystemBadge(short: short, colour: system?.accent ?? Sov.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title).font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                            if let release = game.release {
                                Text(release).font(.system(size: 14, weight: .medium)).foregroundStyle(Sov.amber200)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let save = game.autoSave {
                            Fact(symbol: "square.and.arrow.down", text: "Saved \(formatAgo(Int64(save.savedAt), now: now))")
                        }
                        if game.playCount > 0 {
                            Fact(symbol: "clock.arrow.circlepath",
                                 text: "Played \(game.playCount)× · last \(formatAgo(GameIndex.playedAt(game.lastPlayedAt), now: now))")
                        }
                    }
                    HStack(spacing: 8) {
                        // A game played without an auto save (it never got one) has nothing to continue.
                        if game.autoSave != nil {
                            Button { onPlay(.continue) } label: { Label("Continue", systemImage: "play.fill") }.buttonStyle(.sov())
                        } else {
                            Button { onPlay(.new) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.sov())
                        }
                        Button(action: onDetails) { Label("Game details", systemImage: "info.circle") }
                            .buttonStyle(.sov(.outline))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Sov.surface)
    }

    /// The auto save's screenshot, whole and on black like a TV; the game's artwork if there is none.
    private func leftOff(short: String) -> some View {
        ZStack {
            if let shot = game.autoSave?.screenshotUrl {
                Color.black
                RemoteImage(path: shot, contentMode: .fit, pixelated: true)
            } else {
                tile(system?.accent ?? Sov.accent)
                Text(short).font(.system(size: 60, weight: .black)).foregroundStyle(.white.opacity(0.8))
                RemoteImage(path: game.image ?? game.thumb, contentMode: game.image != nil ? .fill : .fit)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.5), in: Circle())
            }
            .padding(12)
        }
    }
}
