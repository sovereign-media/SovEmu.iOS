import Foundation

/// *Sign in a TV* on the iPhone or iPad (Sovereign's `clients-sign-in-a-tv.md`): type the code a
/// TV's *Sign in with your phone* screen shows, and the app approves it with its own sign-in (the
/// `approveDeviceCode` mutation), so nobody signs in twice. The words, the code's formatting, and
/// what each answer means, as SovEmu.Android's `TvSignIn`.
public enum TvSignIn {
    public static let title = "Sign in a TV"
    public static let intro = "Enter the code your TV is showing."
    public static let fieldLabel = "TV code"
    public static let continueLabel = "Continue"
    public static let approve = "Approve"
    public static let cancel = "Cancel"
    public static let approved = "Your TV is signing in."

    static let codeLength = 8

    /// `Sign in a TV to <server> as <name>?`
    public static func confirmation(server: String, name: String) -> String { "Sign in a TV to \(server) as \(name)?" }

    /// The code's characters: letters and digits only, upper case, at most eight.
    public static func normalize(_ input: String) -> String {
        String(input.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.uppercased().prefix(codeLength))
    }

    /// The code as the TV shows it (`QG3W-RY4W`).
    public static func format(_ input: String) -> String {
        let code = normalize(input)
        return code.count > 4 ? "\(code.prefix(4))-\(code.dropFirst(4))" : code
    }

    /// Whether all eight characters are there: `Continue`'s gate.
    public static func isComplete(_ input: String) -> Bool { normalize(input).count == codeLength }

    /// What the screen says when the approval failed with `error`.
    public static func failure(_ error: Error) -> String {
        switch (error as? APIError)?.code {
        case "NOT_FOUND": "No TV is waiting with that code. Check the code, and that the TV is connected to this server."
        case "TOO_MANY_REQUESTS": "Too many codes just now. Try again in a minute."
        case "UNAUTHENTICATED": "Sign in again to sign in a TV."
        default: error.localizedDescription
        }
    }
}
