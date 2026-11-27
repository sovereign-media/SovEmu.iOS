// SovEmu.Android's `AccountsTest.kt`, case for case.
import Foundation
import Testing
@testable import SovEmuKit

struct AccountsTests {
    private func account(_ id: String, _ server: String = "http://tv.local:8080", name: String? = "ada") -> StoredAccount {
        StoredAccount(id: id, subject: "sub-\(id)", server: server, clientId: "sovemu-native", userName: name, lastUsedAt: 0)
    }

    /// A field holding the codec's own separators or escape must come back as it went in.
    @Test func theCodecRoundTripsEveryField() {
        let accounts = [
            StoredAccount(id: "a", subject: "7", server: "http://x:8080", clientId: "phone-app", userName: "ada\tlovelace\n%", lastUsedAt: 1700),
            StoredAccount(id: "b", subject: "8", server: "https://y", clientId: nil, userName: nil, lastUsedAt: 0),
            StoredAccount(id: "c", subject: "", server: "http://z", clientId: "", userName: "", lastUsedAt: 5),
        ]
        #expect(StoredAccountCodec.decode(StoredAccountCodec.encode(accounts)) == accounts)
    }

    /// The exact bytes Android writes: the format is shared, and a change would lose every account.
    @Test func theCodecWritesAndroidsV1Format() {
        let encoded = StoredAccountCodec.encode([
            StoredAccount(id: "a", subject: "7", server: "http://x", clientId: nil, userName: "a\tb%", lastUsedAt: 12),
        ])
        #expect(encoded == "v1\n+a\t+7\t+http://x\t-\t+a%09b%25\t+12")
    }

    /// A damaged record must not keep the app from the accounts that decode.
    @Test func aDamagedBlobGivesTheAccountsThatDecode() {
        let good = StoredAccountCodec.encode([account("a"), account("b")])
        let lines = good.components(separatedBy: "\n")
        let damaged = [lines[0], lines[1], "+x\t-\tbroken", lines[2], lines[1]].joined(separator: "\n")
        // The broken record is skipped and the duplicate id dropped.
        #expect(StoredAccountCodec.decode(damaged).map(\.id) == ["a", "b"])
        #expect(StoredAccountCodec.decode("v9\n" + lines[1]).isEmpty)
        #expect(StoredAccountCodec.decode(nil).isEmpty)
        #expect(StoredAccountCodec.decode(lines[0] + "\n+a\t-\t+s\t-\t-\t+%zz").isEmpty)
    }

    /// A server reached over https one day and http the next keeps its accounts.
    @Test func oneServerWhicheverSchemeItAnsweredOn() {
        #expect(StoredAccount.sameServer("http://TV.local:8080/", "https://tv.local:8080"))
        #expect(!StoredAccount.sameServer("http://tv.local:8080", "http://tv.local:8081"))
        #expect(!StoredAccount.sameServer(nil, "http://tv.local"))
        #expect(!StoredAccount.sameServer("", ""))
    }

    /// The picker and *Choose a server* have room for exactly this many.
    @Test func fiveUsersAServerAndThreeServersADevice() {
        let five = (1...5).map { account("\($0)") }
        #expect(StoredAccount.refusalFor(Array(five.prefix(4)), server: "http://tv.local:8080") == nil)
        #expect(StoredAccount.refusalFor(five, server: "http://tv.local:8080") == .serverFull)
        let three = [account("a", "http://a"), account("b", "http://b"), account("c", "http://c")]
        #expect(StoredAccount.refusalFor(three, server: "http://d") == .deviceFull)
        // Another user on a server the device already holds still fits.
        #expect(StoredAccount.refusalFor(three, server: "https://b") == nil)
    }

    /// Two or more accounts must never refresh anyone before someone is chosen.
    @Test func aLaunchDecidesByTheCount() {
        #expect(LaunchAccounts.decide(0) == .login)
        #expect(LaunchAccounts.decide(1) == .restore)
        #expect(LaunchAccounts.decide(2) == .picker)
    }

    @Test func chooseAServerListsEachServerOnceInOrder() {
        let accounts = [
            account("a", "http://one", name: "ada"),
            account("b", "http://two", name: "ben"),
            account("c", "https://ONE/", name: "cy"),
        ]
        let list = KnownServers.list(accounts, current: "https://one")
        #expect(list.map(\.address) == ["https://one", "http://two"])
        #expect(list[0].countLine == "2 users  ·  in use")
        #expect(list[1].countLine == "1 user")
        #expect(list[0].removeMessage == "Everyone signed in to it on this device will be signed out: ada, cy.")
        #expect(KnownServers.successor(list, removed: list[0]) == list[1])
        #expect(KnownServers.successor(list, removed: list[1]) == list[0])
        #expect(KnownServers.successor(Array(list.prefix(1)), removed: list[0]) == nil)
        #expect(!KnownServers.canAddServer(3))
    }

    /// An account is keyed on `sub`: a token that cannot be read is nobody, never a crash.
    @Test func anIdTokenSaysWhoSignedIn() {
        #expect(IdToken.read(idToken("7", "ada")) == IdToken(subject: "7", userName: "ada"))
        #expect(IdToken.read(idToken("7")) == IdToken(subject: "7", userName: nil))
        #expect(IdToken.read("x.y.z") == .empty)
        #expect(IdToken.read(nil) == .empty)
        #expect(IdToken.read("nodots") == .empty)
        let numeric = base64URL(#"{"sub":42}"#)
        #expect(IdToken.read("h.\(numeric).s").subject == "42")
    }

    @Test func anAccountIsLabelledByItsUsername() {
        #expect(account("a").initials == "AD")
        #expect(account("a", name: nil).label == "?")
    }
}
