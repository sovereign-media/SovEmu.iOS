import Foundation

// MARK: - Signing in with a code (RFC 8628, the device grant), as Sovereign's TVs do
//
// The app shows a short code; the person approves it on a phone or computer signed in to the
// server (`DeviceCode.verificationURI`, the server's `/device` page); the app's poll of the token
// endpoint then gets its tokens. The password form is the fallback. Same as SovEmu.Android's
// `DevicePairing.kt`, with the same cases in `DevicePairingTests`.

/// A code to show, from the server's device authorization endpoint. `deviceCode` is the
/// credential the poll presents: never shown, and left out of `description`.
public struct DeviceCode: Sendable, Equatable, CustomStringConvertible {
    let deviceCode: String
    /// What the person types: eight characters, grouped by the server as `ABCD-EFGH`.
    public let userCode: String
    /// Where they type it.
    public let verificationURI: String
    /// The same page with the code filled in: what the QR code holds, when the server sends it.
    public let verificationURIComplete: String?
    /// Seconds the code is good for.
    public let expiresIn: Double
    /// Seconds to wait between polls: the server's, never a guess.
    public let interval: Double

    /// RFC 8628's default, for a server that sends no `interval`.
    static let defaultInterval: Double = 5

    public init(
        deviceCode: String, userCode: String, verificationURI: String, verificationURIComplete: String?,
        expiresIn: Double, interval: Double
    ) {
        (self.deviceCode, self.userCode, self.verificationURI) = (deviceCode, userCode, verificationURI)
        (self.verificationURIComplete, self.expiresIn, self.interval) = (verificationURIComplete, expiresIn, interval)
    }

    /// The code as it goes on screen, grouped in fours however the server sent it.
    public var grouped: String {
        let bare = userCode.filter { $0 != "-" && $0 != " " }
        return bare.count == 8 ? "\(bare.prefix(4))-\(bare.suffix(4))" : userCode
    }

    /// What the QR code holds: the page with the code in it, else the page.
    public var qrContent: String { verificationURIComplete ?? verificationURI }

    /// The page without its scheme, as a person types it (`192.168.1.10:8080/device`).
    public var shownURI: String {
        verificationURI.range(of: "://").map { String(verificationURI[$0.upperBound...]) } ?? verificationURI
    }

    public var description: String { "DeviceCode(userCode: \(userCode), verificationURI: \(verificationURI))" }
}

/// One answer from the token endpoint to the device_code grant.
public enum DevicePoll: Sendable, Equatable {
    /// `authorization_pending`: nobody has approved it yet. Not a failure: keep waiting.
    case pending
    /// `slow_down` (or a 429): wait five seconds longer from now on (RFC 8628 section 3.5).
    case slowDown
    /// The request got no answer (offline, a server error). The next poll is the retry.
    case noAnswer
    /// Approved: the tokens are kept, signed in.
    case approved
    /// The server said no, for good.
    case refused(PairingFailure)
}

/// Why a code stopped without signing in.
public enum PairingFailure: Sendable, Equatable {
    /// The code's lifetime ran out: offer a new one.
    case expired
    /// The person said no.
    case denied
    /// Anything else the server refused.
    case failed

    /// What the screen says, for people.
    public var message: String {
        switch self {
        case .expired: "That code has expired."
        case .denied: "The sign-in was declined."
        case .failed: "The server refused the sign-in."
        }
    }
}

/// How waiting for an approval ended.
public enum PairingResult: Sendable, Equatable {
    case approved
    case failed(PairingFailure)
}

/// Polls for `code`'s approval until the server answers for good or the code's lifetime runs
/// out. Waits `code.interval` before each poll (first too, so the request that got the code is
/// not doubled), five seconds longer after each `slow_down`, and treats a poll that got no answer
/// as nothing happening. `reachable` is told whether the last poll got an answer. Cancel the
/// calling task to stop.
///
/// - Parameters:
///   - now: a monotonic clock, in seconds.
///   - sleep: waits that many seconds.
public func awaitApproval(
    _ code: DeviceCode,
    poll: @Sendable () async throws -> DevicePoll,
    now: @Sendable () -> Double,
    sleep: @Sendable (Double) async throws -> Void,
    reachable: @Sendable (Bool) -> Void = { _ in }
) async throws -> PairingResult {
    let deadline = now() + max(code.expiresIn, 1)
    var interval = max(code.interval, 1)
    while true {
        let left = deadline - now()
        if left <= 0 { return .failed(.expired) }
        try await sleep(min(interval, left))
        if now() >= deadline { return .failed(.expired) }
        switch try await poll() {
        case .pending: reachable(true)
        case .noAnswer: reachable(false)
        case .slowDown:
            reachable(true)
            interval += slowDownStep
        case .approved: return .approved
        case .refused(let failure): return .failed(failure)
        }
    }
}

/// RFC 8628 section 3.5: `slow_down` adds five seconds to the interval, for good.
let slowDownStep: Double = 5

/// The screen's words, the same as SovEmu.Android's and Sovereign's TVs where they say the same.
public enum PairingText {
    public static let title = "Sign in with your phone"
    public static let goTo = "On your phone or computer, go to"
    public static let enter = "and enter this code:"
    public static let waiting = "Waiting for you to approve…"
    public static let trouble = "Having trouble reaching the server…"
    public static let asking = "Asking the server for a code…"
    public static let newCode = "Get a new code"
    public static let usePassword = "Use a password instead"
    public static let useCode = "Sign in with your phone"

    /// `Expires in 9:41`.
    public static func expiresIn(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return "Expires in \(s / 60):\(String(format: "%02d", s % 60))"
    }
}
