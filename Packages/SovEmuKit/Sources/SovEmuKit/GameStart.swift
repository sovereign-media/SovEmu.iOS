import Foundation

// The loading screen while a game starts, as the other clients' (SovEmu.Web's launch.ts,
// SovEmu.Android's GameStart.kt): the server's phases (saving the last session, starting the
// emulator, opening the core, reading the game) turned into one bar that only moves forward,
// then connecting, the worker's check of the connection (`0x83`, #243), and the wait for the
// first picture, which the server cannot see.
//
// Reading the game is most of a slow start. When the server knows how much it will read the bar
// is exact; when the core reads a disc itself it is not, and the bar eases towards the end of
// that phase instead (always moving, never arriving) while the megabytes read count up.

/// One line of the loading screen: `label`, its `detail` (megabytes and seconds, or the error),
/// `fraction` 0...1 along the whole start.
public struct LaunchView: Sendable, Equatable {
    public let label: String
    public let detail: String
    public let fraction: Double

    public init(label: String, detail: String, fraction: Double) {
        (self.label, self.detail, self.fraction) = (label, detail, fraction)
    }
}

private struct Phase {
    let from: Double, to: Double
    let label: String
    let ease: Double
}

/// Each phase's share of the bar, and what it is called.
private let phases: [StartPhase: Phase] = [
    .stopping: Phase(from: 0, to: 0.08, label: "Saving your last game", ease: 3000),
    .launching: Phase(from: 0.08, to: 0.12, label: "Starting the emulator", ease: 1000),
    .core: Phase(from: 0.12, to: 0.18, label: "Loading the emulator", ease: 1500),
    .content: Phase(from: 0.18, to: 0.85, label: "Loading the game", ease: 15000),
    // Ready leaves the bar's last stretch to checking the connection and the first picture.
    .ready: Phase(from: 0.85, to: 0.85, label: "Ready", ease: 1),
    .failed: Phase(from: 0, to: 0, label: "Could not start", ease: 1),
]

/// A phase a newer server knows and this app does not: named generically, the bar left where it was.
private let unknownPhase = Phase(from: 0, to: 0, label: "Starting", ease: 1)

private let mebibyte = 1024.0 * 1024.0

/// Megabytes as the other clients write them: whole from 100 MB, else to one decimal (no `.0`).
private func megabytes(_ bytes: Double) -> String {
    let x = bytes >= 100 * mebibyte ? (bytes / mebibyte + 0.5).rounded(.down) : ((bytes / mebibyte * 10 + 0.5).rounded(.down)) / 10
    return x == x.rounded(.down) ? String(Int64(x)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), x)
}

public func describeStart(_ s: StartStatus) -> LaunchView {
    let p = phases[s.phase] ?? unknownPhase
    if s.phase == .failed { return LaunchView(label: p.label, detail: s.error ?? "", fraction: 0) }
    let within: Double
    if let total = s.total, total > 0, let read = s.read {
        within = min(1, read / total)
    } else {
        within = 1 - exp(-s.phaseMs / p.ease)
    }
    var parts: [String] = []
    if s.phase == .content, let read = s.read, read > 0 {
        if let total = s.total, total != 0 {
            parts.append("\(megabytes(min(read, total))) of \(megabytes(total)) MB")
        } else {
            parts.append("\(megabytes(read)) MB read")
        }
    }
    let seconds = Int64((s.elapsedMs / 1000).rounded(.down))
    if seconds >= 3 { parts.append("\(seconds) s") }
    return LaunchView(label: p.label, detail: parts.joined(separator: " · "), fraction: p.from + (p.to - p.from) * within)
}

/// How to leave a start that is slow, stuck or failed, under the loading bar: as terse as the
/// web's `Menu: Esc / Select+Start`, with the ☰ button; on an Apple TV the remote's Back (or
/// Play/Pause) opens it, as Android TV's `Menu: Back / Select+Start` says.
#if os(tvOS)
public let loadingHint = "Menu: Back / Select+Start"
#else
public let loadingHint = "Menu: ☰ / Select+Start"
#endif

/// What opens the menu, in the wait for a first picture: the ☰ button, or a TV remote's Back.
#if os(tvOS)
private let menuKey = "Back"
#else
private let menuKey = "☰"
#endif

/// After this long without a picture the wait says how to get out of it.
public let noPictureHintMs: Int64 = 20_000

/// Where the check of the connection takes the bar: from the session being ready to almost full.
private let network = (from: 0.85, to: 0.97)

/// The session is ready and this app is reaching it (ICE, then DTLS): nothing to show of the
/// game yet, and the worker's check of the connection comes once connected.
public func describeConnecting(waitedMs: Int64) -> LaunchView {
    let seconds = waitedMs / 1000
    return LaunchView(label: "Connecting", detail: seconds >= 3 ? "\(seconds) s" : "", fraction: network.from)
}

/// The check of the player's connection before the stream starts (`0x83`, #243): the worker
/// sends no video meanwhile, so it runs between the session being ready and the first picture.
/// The bar follows its time against its budget. Where the player is shows in a chip of its own
/// (`LinkLabels.networkLabel`).
public func describeLink(_ link: WireProtocol.Link) -> LaunchView {
    let within = link.budgetMs > 0 ? min(1, Double(link.elapsedMs) / Double(link.budgetMs)) : 1
    return LaunchView(label: "Checking your connection", detail: "", fraction: network.from + (network.to - network.from) * within)
}

/// The last stretch of a start, which the server cannot see: the session is ready (and the
/// connection checked), and the game has yet to draw its first picture (a console's BIOS boots
/// for seconds; a save is loaded once the game is up). The detail counts the wait. (The ☰
/// button, where the web says Escape and Android Back; Back on an Apple TV too.)
public func describeFirstPicture(waitedMs: Int64) -> LaunchView {
    let seconds = waitedMs / 1000
    var parts: [String] = []
    if seconds >= 3 { parts.append("\(seconds) s") }
    if waitedMs >= noPictureHintMs { parts.append("still no picture: \(menuKey) opens the menu") }
    return LaunchView(label: "Starting the game", detail: parts.joined(separator: " · "), fraction: network.to)
}

/// The loading screen's background: a picture, and how it is drawn.
public struct LoadingBackground: Sendable, Equatable {
    public let url: String
    /// A save's screenshot, at the console's own resolution: drawn with sharp pixels.
    public let pixelated: Bool
    /// Box art, which is not a picture of the game being played: blurred into a backdrop.
    public let blurred: Bool

    public init(url: String, pixelated: Bool = false, blurred: Bool = false) {
        (self.url, self.pixelated, self.blurred) = (url, pixelated, blurred)
    }
}

/// What the loading screen shows behind the start (#243), first found of: the screenshot of the
/// save being continued, the game's own screenshot, its box art (blurred). Nil leaves the
/// system's colour.
public func loadingBackground(saveShot: String?, image: String?, boxArt: String?) -> LoadingBackground? {
    if let saveShot, !saveShot.isEmpty { return LoadingBackground(url: saveShot, pixelated: true) }
    if let image, !image.isEmpty { return LoadingBackground(url: image) }
    if let boxArt, !boxArt.isEmpty { return LoadingBackground(url: boxArt, blurred: true) }
    return nil
}

/// The loading screen's status line once the emulator is up: `FCEUmm · 256×224 @ 60.10 fps`.
public func loadingStatus(core: String, width: Int, height: Int, fps: Double) -> String {
    "\(core) · \(width)×\(height) @ \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), fps)) fps"
}

/// Keeps a bar from ever moving backwards (a phase can report less than the one before).
public struct ForwardOnly: Sendable {
    private var highest = 0.0

    public init() {}

    public mutating func next(_ fraction: Double) -> Double {
        highest = max(highest, min(1, max(0, fraction)))
        return highest
    }
}

/// An id for following one start (letters, digits and dashes, as the server requires).
public func newStartId() -> String { UUID().uuidString }

/// What the player's loading screen shows: `label` and `detail`, over a bar at `fraction` (nil:
/// no bar, an error).
public struct StartScreen: Sendable, Equatable {
    public let label: String
    public let detail: String
    public let fraction: Double?

    public init(label: String, detail: String = "", fraction: Double? = nil) {
        (self.label, self.detail, self.fraction) = (label, detail, fraction)
    }
}

/// The loading screen, one state for the whole start.
public enum GameStart {
    /// `error` (a failure to start, or a lost connection) wins; then the session starting
    /// (`ready` not yet), with the server's `progress` once it has said (a FAILED start shows its
    /// error); then, until `pictureShown`: connecting until the worker's first `link` (an older
    /// worker sends none, and its picture comes at once), the check of the connection while it
    /// is `probing`, and the wait for the picture, `waitedMs` so far; then nil. The bar never
    /// falls below `bar`, the furthest it has been.
    public static func screen(
        title: String, error: String?, progress: StartStatus?, bar: Double, ready: Bool, link: WireProtocol.Link? = nil,
        pictureShown: Bool, waitedMs: Int64
    ) -> StartScreen? {
        if let error { return StartScreen(label: error) }
        if !ready {
            guard let progress else { return StartScreen(label: "Starting \(title)…", fraction: bar) }
            let view = describeStart(progress)
            return progress.phase == .failed
                ? StartScreen(label: view.label, detail: view.detail)
                : StartScreen(label: view.label, detail: view.detail, fraction: bar)
        }
        if pictureShown { return nil }
        let view = if let link {
            link.state == WireProtocol.Link.probing ? describeLink(link) : describeFirstPicture(waitedMs: waitedMs)
        } else {
            describeConnecting(waitedMs: waitedMs)
        }
        return StartScreen(label: view.label, detail: view.detail, fraction: max(bar, view.fraction))
    }
}
