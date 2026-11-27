// What the accounts suites share, as SovEmu.Android's `AccountFixtures.kt`. Its `MemoryKeyValue`
// is SovEmuKit's own (previews use it too); its `FakeSealer` has no counterpart, as the Keychain
// keeps a token whole (`MemoryAccountTokenStore` stands in for it).
import Foundation
@testable import SovEmuKit

/// An ID token as SovEmu's server signs one (the signature is not checked by the app).
func idToken(_ subject: String, _ userName: String? = nil) -> String {
    var claims = #"{"iss":"http://sovemu","sub":"\#(subject)""#
    if let userName { claims += #","preferred_username":"\#(userName)""# }
    claims += "}"
    return base64URL(#"{"alg":"ES256"}"#) + "." + base64URL(claims) + ".signature"
}

/// Base64url without padding, as a JWT's parts are.
func base64URL(_ text: String) -> String {
    Data(text.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

extension AccountUpsert {
    /// The account stored, or nil when refused (Kotlin's `as AccountUpsert.Stored`).
    var stored: StoredAccount? {
        if case .stored(let account) = self { return account }
        return nil
    }
}
