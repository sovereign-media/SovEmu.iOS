import Foundation

// The loading screen while a game starts, as the other clients' (SovEmu.Web's launch.ts,
// SovEmu.Android's GameStart.kt): the server's phases (saving the last session, starting the
// emulator, opening the core, reading the game) turned into one bar that only moves forward,
// then the wait for the first picture, which the server cannot see.
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
    .content: Phase(from: 0.18, to: 0.97, label: "Loading the game", ease: 15000),
    .ready: Phase(from: 1, to: 1, label: "Ready", ease: 1),
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

/// After this long without a picture the wait says how to get out of it.
public let noPictureHintMs: Int64 = 20_000

/// The last stretch of a start, which the server cannot see: the session is ready, and the game
/// has yet to draw its first picture (a console's BIOS boots for seconds; a save is loaded once
/// the game is up). The bar is full; the detail counts the wait. (The ☰ button, where the web
/// says Escape and Android Back.)
public func describeFirstPicture(waitedMs: Int64) -> LaunchView {
    let seconds = waitedMs / 1000
    var parts: [String] = []
    if seconds >= 3 { parts.append("\(seconds) s") }
    if waitedMs >= noPictureHintMs { parts.append("still no picture: ☰ opens the menu") }
    return LaunchView(label: "Starting the game", detail: parts.joined(separator: " · "), fraction: 1)
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
    /// error); then, until `pictureShown`, the wait for it, `waitedMs` so far; then nil.
    public static func screen(
        title: String, error: String?, progress: StartStatus?, bar: Double, ready: Bool, pictureShown: Bool, waitedMs: Int64
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
        let view = describeFirstPicture(waitedMs: waitedMs)
        return StartScreen(label: view.label, detail: view.detail, fraction: view.fraction)
    }
}
