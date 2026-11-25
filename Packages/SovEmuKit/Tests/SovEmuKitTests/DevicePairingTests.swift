import Foundation
import Synchronization
import Testing
@testable import SovEmuKit

/// Signing in with a code: the same cases as SovEmu.Android's `DevicePairingTest` (the wait
/// loop, on a clock the test moves) and its `AuthTest` (the code request and every poll answer).
struct DevicePairingTests {
    private let code = DeviceCode(
        deviceCode: "dc", userCode: "BCDF-GHJK", verificationURI: "http://tv.local/device",
        verificationURIComplete: nil, expiresIn: 60, interval: 5)

    /// A clock that moves only when the loop sleeps, and what it slept.
    private final class Clock: Sendable {
        let state = Mutex<(now: Double, waits: [Double])>((0, []))
        var now: Double { state.withLock { $0.now } }
        var waits: [Double] { state.withLock { $0.waits } }
        func sleep(_ s: Double) { state.withLock { $0.now += s; $0.waits.append(s) } }
    }

    /// Answers in order, then `pending` for ever; and what `reachable` was told.
    private final class Answers: Sendable {
        let queue: Mutex<[DevicePoll]>
        let reach = Mutex<[Bool]>([])
        init(_ answers: [DevicePoll]) { queue = Mutex(answers) }
        func next() -> DevicePoll { queue.withLock { $0.isEmpty ? .pending : $0.removeFirst() } }
    }

    private func pairing(_ answers: DevicePoll..., clock: Clock = Clock(), seen: Answers? = nil) async throws -> PairingResult {
        let answers = seen ?? Answers(answers)
        return try await awaitApproval(
            code, poll: { answers.next() }, now: { clock.now }, sleep: { clock.sleep($0) },
            reachable: { ok in answers.reach.withLock { $0.append(ok) } })
    }

    @Test func waitingIsNotAFailureAndTheServersIntervalIsKept() async throws {
        let clock = Clock()
        #expect(try await pairing(.pending, .pending, .approved, clock: clock) == .approved)
        // The wait comes first, so the request that got the code is not doubled at once.
        #expect(clock.waits == [5, 5, 5])
    }

    @Test func slowDownWidensTheIntervalForGood() async throws {
        let clock = Clock()
        #expect(try await pairing(.slowDown, .pending, .slowDown, .refused(.denied), clock: clock) == .failed(.denied))
        #expect(clock.waits == [5, 10, 10, 15])
    }

    @Test func aPollWithNoAnswerIsTriedAgainAndSaidSo() async throws {
        let seen = Answers([.noAnswer, .noAnswer, .pending, .approved])
        #expect(try await pairing(seen: seen) == .approved)
        #expect(seen.reach.withLock { $0 } == [false, false, true])
    }

    @Test func aCodeNobodyApprovesExpiresWithItsLifetime() async throws {
        let clock = Clock()
        // Pending for ever: the 60 s lifetime ends it, without a poll past it.
        #expect(try await pairing(clock: clock) == .failed(.expired))
        #expect(clock.waits.reduce(0, +) == 60 && clock.waits.count == 12)
    }

    @Test func theCodeIsShownGroupedAndCountsDown() {
        let bare = DeviceCode(
            deviceCode: "secret", userCode: "BCDFGHJK", verificationURI: "http://192.168.1.10:8080/device",
            verificationURIComplete: "http://192.168.1.10:8080/device?user_code=BCDF-GHJK", expiresIn: 600, interval: 5)
        #expect(bare.grouped == "BCDF-GHJK" && code.grouped == "BCDF-GHJK")
        #expect(bare.shownURI == "192.168.1.10:8080/device")
        #expect(bare.qrContent == "http://192.168.1.10:8080/device?user_code=BCDF-GHJK")
        #expect(code.qrContent == "http://tv.local/device", "the page, when the server sends no complete one")
        #expect(!bare.description.contains("secret"), "the credential never goes in a log line")
        #expect(PairingText.expiresIn(545) == "Expires in 9:05" && PairingText.expiresIn(-3) == "Expires in 0:00")
    }

    // MARK: Against the server

    private func client(_ stub: Stub, store: MemoryTokenStore = MemoryTokenStore()) -> TokenClient {
        let endpoints = SignInEndpoints(
            clientId: "sovemu-native", token: stub.base.appending(path: "oauth/token"), revocation: nil, password: nil,
            deviceAuthorization: stub.base.appending(path: "oauth/device_authorization"))
        return TokenClient(baseURL: stub.base, endpoints: endpoints, store: store, session: stub.session)
    }

    @Test func aCodeIsAskedForAsTheDeviceClient() async throws {
        let stub = Stub { _, _ in
            (200, Stub.json([
                "device_code": "secret-device-code", "user_code": "BCDF-GHJK", "verification_uri": "http://tv.local/device",
                "verification_uri_complete": "http://tv.local/device?user_code=BCDF-GHJK", "expires_in": 600, "interval": 5,
            ]))
        }
        let code = try await client(stub).requestDeviceCode()
        #expect(stub.requests.first?.path == "/oauth/device_authorization")
        #expect(stub.requests.first?.form == ["client_id": "sovemu-native", "scope": TokenClient.scope])
        #expect(code.grouped == "BCDF-GHJK" && code.expiresIn == 600 && code.interval == 5)
        #expect(code.qrContent == "http://tv.local/device?user_code=BCDF-GHJK")
    }

    @Test func aPollSaysWhatTheServerSaidAndAnApprovalSignsIn() async throws {
        let answers: [(Int, String)] = [
            (400, #"{"error":"authorization_pending"}"#), (400, #"{"error":"slow_down"}"#), (429, #"{"error":"too_many_requests"}"#),
            (503, "<html>"), (400, #"{"error":"access_denied"}"#), (400, #"{"error":"expired_token"}"#),
            (400, #"{"error":"invalid_grant"}"#), Stub.tokens("a1", "r1"),
        ]
        let count = Counter()
        let stub = Stub { _, _ in answers[count.next() - 1] }
        let store = MemoryTokenStore()
        let client = client(stub, store: store)
        var seen: [DevicePoll] = []
        for _ in answers { seen.append(try await client.pollDeviceCode(code)) }
        #expect(seen == [.pending, .slowDown, .slowDown, .noAnswer, .refused(.denied), .refused(.expired), .refused(.failed), .approved])
        let poll = try #require(stub.requests.first)
        #expect(poll.form == ["grant_type": TokenClient.deviceCodeGrant, "client_id": "sovemu-native", "device_code": "dc"])
        // Approved: signed in, with the tokens kept.
        #expect(store.load() == "r1")
        #expect(try await client.accessToken() == "a1")
    }
}
