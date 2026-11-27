import AVFoundation
import Foundation

/// Background music for the menus, as the Android app's: every MP3 bundled in `Music/`,
/// shuffled, one after another (reshuffled after the last), fading in and out. It plays in the
/// ambient category, so the silent switch mutes it and it mixes with what else is playing;
/// a game and the screensaver have their own sound, so it stops for them.
@MainActor
final class MenuMusic: NSObject, AVAudioPlayerDelegate {
    /// Under the menus' sounds: background, not foreground.
    private static let volume: Float = 0.5
    private static let fade: TimeInterval = 0.6

    private let tracks: [URL] = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? []
    private var order: [URL] = []
    private var next = 0
    private var player: AVAudioPlayer?
    private var wanted = false

    /// Whether the menus want music now: fades in or out to match.
    func play(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        if on {
            // A game's WebRTC audio session may have changed the category: put it back first.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            if player == nil { startNext() }
            player?.volume = 0
            player?.play()
            player?.setVolume(Self.volume, fadeDuration: Self.fade)
        } else if let player {
            player.setVolume(0, fadeDuration: Self.fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade) { [weak self] in
                // Paused at silence, keeping its place, unless it was wanted again meanwhile.
                guard let self, !self.wanted else { return }
                self.player?.pause()
            }
        }
    }

    private func startNext() {
        guard !tracks.isEmpty else { return }
        if next == 0 || order.isEmpty { order = tracks.shuffled() }
        let url = order[next % order.count]
        next = (next + 1) % order.count
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.startNext()
            guard self.wanted else { return }
            self.player?.volume = Self.volume
            self.player?.play()
        }
    }
}
