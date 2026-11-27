// SovEmu.Android's `AccountStoreTest.kt`, case for case, then the account halves of its
// `Session` that `AccountStore` holds here.
import Foundation
import Synchronization
import Testing
@testable import SovEmuKit

struct AccountStoreTests {
    private let prefs = MemoryKeyValue()
    private let tokens = MemoryAccountTokenStore()

    private func store(tokens: (any AccountTokenStore)? = nil) -> AccountStore {
        let ids = Counter()
        return AccountStore(values: prefs, tokens: tokens ?? self.tokens, newId: { "id\(ids.next())" })
    }

    /// Signing in again as someone already here must not add a second tile for them.
    @Test func theSameUserOnTheSameServerIsOneAccount() throws {
        let store = store()
        let first = try #require(store.upsert(subject: "7", server: "http://tv.local:8080", clientId: "c", userName: "ada", now: 1).stored)
        store.setNamedDevice(first.id, "TV")
        let again = try #require(store.upsert(subject: "7", server: "https://TV.local:8080", clientId: "c2", userName: nil, now: 2).stored)
        #expect(again.id == first.id)
        #expect(again.clientId == "c2")
        #expect(again.userName == "ada")
        #expect(store.namedDevice(first.id) == nil, "a new sign-in has no device name yet")
        // Another user, or the same user on another server, is another account.
        _ = store.upsert(subject: "8", server: "http://tv.local:8080", clientId: "c", userName: "ben", now: 3)
        _ = store.upsert(subject: "7", server: "http://other:8080", clientId: "c", userName: "ada", now: 4)
        #expect(store.all().count == 3)
    }

    /// Nobody is signed out to make room.
    @Test func aSixthUserIsRefusedAndNothingChanges() {
        let store = store()
        for i in 0..<5 { _ = store.upsert(subject: "\(i)", server: "http://tv.local:8080", clientId: "c", userName: nil, now: 0) }
        let before = store.all()
        #expect(store.upsert(subject: "9", server: "http://tv.local:8080", clientId: "c", userName: nil, now: 0) == .refused(.serverFull))
        #expect(store.all() == before)
        // The same user signing in again still fits.
        #expect(store.upsert(subject: "3", server: "http://tv.local:8080", clientId: "c", userName: nil, now: 0).stored != nil)
    }

    /// A refresh that outlives a sign-out must not bring the removed account's token back.
    @Test func removingAnAccountTakesItsTokenAndTheActiveId() throws {
        let store = store()
        let a = try #require(store.upsert(subject: "7", server: "http://tv.local:8080", clientId: "c", userName: nil, now: 0).stored)
        store.setRefreshToken(a.id, "r1")
        store.setActive(a.id, now: 5)
        #expect(store.account(a.id)?.lastUsedAt == 5)
        store.remove(a.id)
        #expect(store.activeId() == nil)
        #expect(store.refreshToken(a.id) == nil)
        #expect(tokens.load(a.id) == nil)
        // A late write for it (a refresh that outlived the sign-out) is dropped.
        store.setRefreshToken(a.id, "r2")
        #expect(tokens.load(a.id) == nil)
    }

    /// Android's case is a token its key can no longer unseal. Here it is the Keychain without
    /// the item: the defaults came back with a restore, this-device-only items did not. The
    /// account must read as having no token (an expiry), never as a crash or someone else's.
    @Test func aTokenThatCannotBeUnsealedReadsAsNone() throws {
        let a = try #require(store().upsert(subject: "7", server: "http://tv.local:8080", clientId: "c", userName: nil, now: 0).stored)
        store().setRefreshToken(a.id, "r1")
        let restored = store(tokens: MemoryAccountTokenStore())
        #expect(restored.account(a.id) != nil)
        #expect(restored.refreshToken(a.id) == nil)
    }

    @Test func aRefreshTeachesTheAccountItsNameAndClientButNeverAnotherSub() {
        let store = store()
        _ = store.upsert(subject: "7", server: "http://tv.local:8080", clientId: nil, userName: nil, now: 0)
        store.recordRefresh("id1", idToken: IdToken(subject: "7", userName: "ada"), clientId: "sovemu-native")
        #expect(store.account("id1") == StoredAccount(
            id: "id1", subject: "7", server: "http://tv.local:8080", clientId: "sovemu-native", userName: "ada", lastUsedAt: 0))
        // Its sub never changes afterwards.
        store.recordRefresh("id1", idToken: IdToken(subject: "8", userName: nil), clientId: "sovemu-native")
        #expect(store.account("id1")?.subject == "7")
    }

    // MARK: - Session's account halves

    /// A sign-in is keyed on the ID token's `sub`, labelled by its username, and becomes active
    /// with its token; a second sign-in as them replaces it.
    @Test func aSignInIsStoredWithItsTokenAndMadeActive() throws {
        let store = store()
        let a = try #require(store.signedIn(
            idToken: idToken("7", "ada"), refreshToken: "r1", server: "http://tv.local:8080", clientId: nil, now: 9).stored)
        #expect(a.userName == "ada")
        #expect(store.activeId() == a.id)
        #expect(store.refreshToken(a.id) == "r1")
        #expect(store.account(a.id)?.lastUsedAt == 9)
        let again = try #require(store.signedIn(
            idToken: idToken("7"), refreshToken: "r2", server: "http://tv.local:8080", clientId: "m", now: 10).stored)
        #expect(again.id == a.id)
        #expect(store.refreshToken(a.id) == "r2")
        #expect(store.all().count == 1)
    }

    /// Tokens that name nobody, or a new account that does not fit, change nothing: whoever was
    /// signed in stays so (the caller revokes the new token).
    @Test func aRefusedSignInLeavesWhoeverWasSignedIn() throws {
        let store = store()
        let a = try #require(store.signedIn(
            idToken: idToken("1"), refreshToken: "r1", server: "http://tv.local:8080", clientId: nil, now: 0).stored)
        #expect(store.signedIn(idToken: "x.y.z", refreshToken: "bad", server: "http://tv.local:8080", clientId: nil, now: 1)
            == .refused(.noIdentity))
        for i in 2...5 { _ = store.upsert(subject: "\(i)", server: "http://tv.local:8080", clientId: nil, userName: nil, now: 0) }
        #expect(store.signedIn(idToken: idToken("6"), refreshToken: "r6", server: "http://tv.local:8080", clientId: nil, now: 2)
            == .refused(.serverFull))
        #expect(store.activeId() == a.id)
        #expect(store.all().count == 5)
        #expect(!tokens.all.values.contains("bad") && !tokens.all.values.contains("r6"))
    }

    /// A launch with two or more accounts on the server must leave nobody active (no refresh
    /// before someone is chosen); one is made active; none clears the active one.
    @Test func aLaunchMakesTheOneAccountActiveAndLeavesTwoToThePicker() throws {
        let store = store()
        let a = try #require(store.upsert(subject: "7", server: "http://one", clientId: nil, userName: nil, now: 0).stored)
        #expect(store.launch(on: "https://ONE/", now: 3) == .restore)
        #expect(store.activeId() == a.id)
        #expect(store.account(a.id)?.lastUsedAt == 3)
        _ = store.upsert(subject: "8", server: "http://one", clientId: nil, userName: nil, now: 0)
        #expect(store.launch(on: "http://one", now: 4) == .picker)
        #expect(store.activeId() == nil)
        store.setActive(a.id, now: 5)
        #expect(store.launch(on: "http://two", now: 6) == .login)
        #expect(store.activeId() == nil)
    }

    /// Removing a server gives back each token for revoking, and only that server's accounts go.
    @Test func removingAServerReturnsItsTokensForRevoking() throws {
        let store = store()
        let a = try #require(store.upsert(subject: "7", server: "http://one", clientId: nil, userName: nil, now: 0).stored)
        let b = try #require(store.upsert(subject: "8", server: "http://two", clientId: nil, userName: nil, now: 0).stored)
        store.setRefreshToken(a.id, "ra")
        store.setRefreshToken(b.id, "rb")
        store.setActive(a.id, now: 0)
        let removal = store.removeServer("https://one")
        #expect(removal.wasActive)
        #expect(removal.removed.map(\.refreshToken) == ["ra"])
        #expect(store.all().map(\.id) == [b.id])
        #expect(store.activeId() == nil)
        #expect(tokens.all == [b.id: "rb"])
        #expect(store.removeServer("http://three") == ServerRemoval(removed: [], wasActive: false))
    }

    /// Two callers at once (a refresh and a sign-in) must never lose an account to a race.
    @Test func concurrentSignInsAllLand() async {
        let store = store()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    _ = store.signedIn(idToken: idToken("\(i)"), refreshToken: "r\(i)", server: "http://one", clientId: nil, now: 0)
                }
            }
        }
        #expect(Set(store.all().map(\.subject)) == ["0", "1", "2", "3", "4"])
        #expect(tokens.all.count == 5)
    }
}
