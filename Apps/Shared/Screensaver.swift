import AVFoundation
import GameController
import SovEmuKit
import SwiftUI
import UIKit

/// When a person last touched the screen or used a controller, for the screensaver. A touch is
/// seen by a recognizer on the window that never takes the touch from the view under it; a
/// controller by polling its buttons and sticks twice a second (the game's own controller code
/// belongs to the player, which is not open while this matters).
@MainActor
@Observable
final class IdleWatcher {
    private(set) var lastInput = Date()
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var poll: Timer?

    func install() {
        guard !installed else { return }
        installed = true
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if Self.anyControllerInput() { self?.touched() }
            }
        }
        attach()
    }

    /// The recognizer goes on the key window once there is one.
    private func attach() {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.attach() }
            return
        }
        let recognizer = TouchSpy { [weak self] in self?.touched() }
        window.addGestureRecognizer(recognizer)
    }

    func touched() { lastInput = Date() }

    private static func anyControllerInput() -> Bool {
        GCController.controllers().contains { c in
            guard let pad = c.extendedGamepad else { return false }
            let pressed = pad.allButtons.contains { $0.isPressed }
            let sticks = [pad.leftThumbstick, pad.rightThumbstick].contains { abs($0.xAxis.value) > 0.5 || abs($0.yAxis.value) > 0.5 }
            return pressed || sticks || pad.dpad.xAxis.value != 0 || pad.dpad.yAxis.value != 0
        } || (GCKeyboard.coalesced?.keyboardInput?.isAnyKeyPressed ?? false)
    }
}

/// Sees every touch on the window and lets it through.
private final class TouchSpy: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(_ onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// The screensaver, as the Android app's: random games' video snaps, one after another (each
/// until it ends, at most 30 s), at a background volume, with a bar along the bottom naming the
/// game, its system, release date and players. Any touch or controller press ends it.
struct ScreensaverView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    let onEnd: () -> Void

    @State private var game: Game?
    @State private var player = AVPlayer()
    @State private var drawing = false
    @State private var aspect: CGFloat = 4 / 3

    private static let clip: Duration = .seconds(30)
    private static let volume: Float = 0.35

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                PlayerLayerView(player: player, gravity: .resizeAspect) { size in
                    if size.width > 0, size.height > 0 { aspect = size.width / size.height }
                }
                .aspectRatio(aspect, contentMode: .fit)
                Color.black.opacity(drawing ? 0 : 1).animation(.easeInOut(duration: 0.4), value: drawing)
            }
            InfoBar(game: game, system: game.flatMap { library.system($0.system) })
                .animation(.easeInOut(duration: 0.4), value: game?.id)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onEnd)
        .task { await cycle() }
        .task {
            // Any controller press ends it, as a touch does.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let pressed = GCController.controllers().contains { $0.extendedGamepad?.allButtons.contains(where: \.isPressed) ?? false }
                if pressed { onEnd() }
            }
        }
        .onDisappear { player.pause() }
    }

    /// One game after another: until its video ends (or fails), at most 30 s.
    private func cycle() async {
        player.volume = Self.volume
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .moviePlayback, options: [.mixWithOthers])
        while !Task.isCancelled {
            guard let next = await library.randomVideoGame(), let url = model.api?.media(next.video) else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            drawing = false
            try? await Task.sleep(for: .milliseconds(400))
            game = next
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.play()
            // The veil lifts once the video can play.
            let watch = Task { @MainActor in
                while !Task.isCancelled && item.status == .unknown { try? await Task.sleep(for: .milliseconds(100)) }
                if item.status == .readyToPlay { drawing = true }
            }
            // Its end, a failure, or 30 s: whichever comes first.
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                        return
                    }
                }
                group.addTask { try? await Task.sleep(for: Self.clip) }
                group.addTask { @MainActor in
                    while !Task.isCancelled && item.status != .failed { try? await Task.sleep(for: .milliseconds(250)) }
                }
                await group.next()
                group.cancelAll()
            }
            watch.cancel()
        }
    }
}

/// The game on screen, as one line of chrome along the bottom: box art, system, title, release
/// date and players.
private struct InfoBar: View {
    let game: Game?
    let system: SystemSummary?

    var body: some View {
        HStack(spacing: 16) {
            if let game {
                if game.thumb != nil {
                    RemoteImage(path: game.thumb, contentMode: .fit).frame(width: 36, height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                SystemBadge(short: system?.short ?? game.system.uppercased(), colour: system?.accent ?? Sov.accent)
                Text(game.title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                if let system { Text(system.name).font(.system(size: 14)).foregroundStyle(Sov.slate400).lineLimit(1) }
                if let date = formatReleaseDate(game.releaseDate) { Fact(symbol: "calendar", text: date) }
                if let players = formatPlayers(game.players) { Fact(symbol: "person.2", text: players) }
                Spacer(minLength: 8)
                Text("Touch to return").font(.system(size: 12)).foregroundStyle(Sov.slate500).lineLimit(1)
            }
        }
        .padding(.horizontal, 32)
        .frame(height: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sov.surface)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }
}

/// An `AVPlayerLayer` in SwiftUI; `onSize` gets the video's presentation size once known.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var onSize: ((CGSize) -> Void)?

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var observation: NSKeyValueObservation?
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .clear
        let report = onSize
        view.observation = player.observe(\.currentItem?.presentationSize, options: [.new]) { player, _ in
            let size = player.currentItem?.presentationSize ?? .zero
            DispatchQueue.main.async { report?(size) }
        }
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.videoGravity = gravity
    }
}

/// A game's video snap, muted and looping, as the game panel plays it on the other clients: it
/// starts after a moment (moving on quickly loads none) and fades in over the artwork once it can
/// play, so the artwork shows until then (and stays, if there is no video or it fails).
struct VideoSnap: View {
    @Environment(AppModel.self) private var model
    let path: String?
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var playing = false

    var body: some View {
        PlayerLayerView(player: player)
            .opacity(playing ? 1 : 0)
            .animation(.easeIn(duration: 0.4), value: playing)
            .allowsHitTesting(false)
            .task(id: path) {
                playing = false
                player.removeAllItems()
                looper = nil
                guard let url = model.api?.media(path) else { return }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                player.isMuted = true
                let item = AVPlayerItem(url: url)
                looper = AVPlayerLooper(player: player, templateItem: item)
                player.play()
                while !Task.isCancelled, player.currentItem?.status != .readyToPlay {
                    if player.currentItem?.status == .failed { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                playing = !Task.isCancelled
            }
            .onDisappear {
                player.pause()
                player.removeAllItems()
            }
    }
}
