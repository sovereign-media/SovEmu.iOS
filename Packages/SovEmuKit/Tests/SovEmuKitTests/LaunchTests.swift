// SovEmu.Android's `LaunchTest.kt`, case for case. Android drives `ServerChooser` with its real
// `Session`; here `TestSession` is what the app's session does with the accounts (Android's
// `Session.launch` and `removeServer`, over `AccountStore`), without tokens.
import Foundation
import Testing
@testable import SovEmuKit

/// Where the app stands, as Android's `AuthState` (without `Expired`, which needs a refresh).
enum TestAuthState: Equatable {
    case signedOut
    case authenticated(String)
    case choosing
}

/// The session's account half: lands by the launch rule and removes servers, as Android's.
actor TestSession: AccountSession {
    let store: AccountStore
    private let servers: FakeServers
    private(set) var state = TestAuthState.signedOut

    init(store: AccountStore, servers: FakeServers) { (self.store, self.servers) = (store, servers) }

    func launch() async -> LaunchAccounts {
        let decision = store.launch(on: await servers.server(), now: 0)
        switch decision {
        case .login: state = .signedOut
        case .restore: state = store.activeId().map(TestAuthState.authenticated) ?? .signedOut
        case .picker: state = .choosing
        }
        return decision
    }

    func removeServer(_ address: String) async -> Bool {
        let removal = store.removeServer(address)
        if removal.wasActive { state = .signedOut }
        return removal.wasActive
    }
}

struct LaunchTests {
    /// Whoever picks up the remote next must not carry on as whoever used it last.
    @Test func thePickerReturnsOnlyAfterAnHourAwayWithSomeoneToChoose() {
        let hour: Int64 = 60 * 60_000
        #expect(IdlePicker.shouldShow(backgroundedAt: 0, now: hour, accounts: 2, playing: false))
        #expect(!IdlePicker.shouldShow(backgroundedAt: 0, now: hour - 1, accounts: 2, playing: false))
        #expect(!IdlePicker.shouldShow(backgroundedAt: 0, now: hour, accounts: 1, playing: false))
        #expect(!IdlePicker.shouldShow(backgroundedAt: 0, now: hour, accounts: 2, playing: true))
        #expect(!IdlePicker.shouldShow(backgroundedAt: nil, now: hour, accounts: 2, playing: false))
        #expect(!IdlePicker.shouldShow(backgroundedAt: 0, now: hour, accounts: 2, playing: false, thresholdMinutes: 0))
    }

    /// The focus engine's geometric search can land on the wrong row of a centred short one.
    @Test func upAndDownGoToTheNearestTileOfACentredRow() {
        // Five accounts and Add user: two full rows of three.
        let full = pickerFocusMoves(count: 6, columns: 3)
        #expect(full[0] == PickerMove(left: nil, right: 1, up: nil, down: 3))
        #expect(full[5] == PickerMove(left: 4, right: nil, up: 2, down: nil))
        // Four tiles: a row of three over one centred tile, which sits under the middle one.
        let four = pickerFocusMoves(count: 4, columns: 3)
        #expect(four[0].down == 3)
        #expect(four[2].down == 3)
        #expect(four[3].up == 1)
        #expect(four[3] == PickerMove(left: nil, right: nil, up: 1, down: nil))
        // Five: two under three, between its columns; a tie goes left.
        let five = pickerFocusMoves(count: 5, columns: 3)
        #expect(five[1].down == 3)
        #expect(five[3].up == 0)
        #expect(five[4].up == 1)
        #expect(pickerFocusMoves(count: 0, columns: 3).isEmpty)
    }

    private func session(_ servers: FakeServers) -> TestSession {
        let ids = Counter()
        let store = AccountStore(values: MemoryKeyValue(), tokens: MemoryAccountTokenStore(), newId: { "id\(ids.next())" })
        for (server, sub) in [("http://one", "7"), ("http://one", "8"), ("http://two", "9"), ("http://three", "7")] {
            _ = store.upsert(subject: sub, server: server, clientId: "c", userName: "u\(sub)", now: 0)
        }
        return TestSession(store: store, servers: servers)
    }

    @Test func choosingAServerLandsByTheLaunchRule() async throws {
        let servers = FakeServers("http://one")
        let session = session(servers)
        let chooser = ServerChooser(service: servers, session: session)
        let list = KnownServers.list(session.store.all(), current: await servers.current)
        #expect(try await chooser.choose(list[0]) == .stayed)
        #expect(try await chooser.choose(list[1]) == .moved(.restore))
        #expect(await servers.current == "http://two")
        #expect(session.store.active()?.userName == "u9")
        let back = KnownServers.list(session.store.all(), current: await servers.current)
        #expect(try await chooser.choose(back[0]) == .moved(.picker))
        #expect(await session.state == .choosing)
    }

    @Test func aServerThatDoesNotAnswerLeavesTheAppWhereItWas() async throws {
        let servers = FakeServers("http://one", down: ["http://two"])
        let session = session(servers)
        _ = await session.launch()
        let list = KnownServers.list(session.store.all(), current: await servers.current)
        let move = try await ServerChooser(service: servers, session: session).choose(list[1])
        guard case .failed(let message) = move else { Issue.record("moved: \(move)"); return }
        #expect(message.hasPrefix("Cannot reach http://two"))
        #expect(await servers.current == "http://one")
        #expect(await session.state == .choosing)
    }

    @Test func removingTheServerInUseMovesToTheOneThatTookItsPlace() async throws {
        let servers = FakeServers("http://two")
        let session = session(servers)
        _ = await session.launch()
        let chooser = ServerChooser(service: servers, session: session)
        var list = KnownServers.list(session.store.all(), current: await servers.current)
        // Not in use: only its accounts go.
        #expect(try await chooser.remove(list[0], from: list) == .stayed)
        #expect(session.store.all().map(\.userName) == ["u9", "u7"])
        list = KnownServers.list(session.store.all(), current: await servers.current)
        #expect(try await chooser.remove(list[0], from: list) == .moved(.restore))
        #expect(await servers.current == "http://three")
        list = KnownServers.list(session.store.all(), current: await servers.current)
        #expect(try await chooser.remove(list[0], from: list) == .noServer)
        #expect(await servers.current == "")
        #expect(await session.state == .signedOut)
    }
}
