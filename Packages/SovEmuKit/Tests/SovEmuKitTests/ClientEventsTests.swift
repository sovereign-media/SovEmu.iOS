import Testing
@testable import SovEmuKit

@Suite struct ClientEventsTests {
    @Test func eachDistinctEventIsSentOnceInBatchesTheServerTakes() {
        let q = ClientEventQueue(now: { 1 })
        #expect(q.add(.connectionFailed, "ICE failed", sessionId: "abc"))
        #expect(!q.add(.connectionFailed, "ICE failed", sessionId: "abc"), "the same fault again")
        #expect(q.take() == [[ClientEvent(kind: .connectionFailed, message: "ICE failed", sessionId: "abc", at: 1)]])
        for i in 0..<25 { q.add(.other, "event \(i)") }
        #expect(q.take().map(\.count) == [20, 5])
        #expect(q.take().isEmpty)
    }

    @Test func longMessagesAreCut() {
        let q = ClientEventQueue(now: { 0 })
        q.add(.other, String(repeating: "x", count: 1000))
        #expect(q.take().first?.first?.message.count == ClientEventQueue.maxMessage)
    }

    @Test func eventsBecomeTheMutationsVariables() {
        let event = ClientEvent(kind: .streamStalled, message: "no new picture", sessionId: nil, at: 2.5)
        let variables = SovEmuAPI.eventVariables(client: "ios", events: [event])
        #expect(variables["client"] == .string("ios"))
        #expect(variables["events"] == .list([.object([
            "kind": .string("STREAM_STALLED"), "message": .string("no new picture"), "sessionId": .null, "at": .double(2.5),
        ])]))
    }
}
