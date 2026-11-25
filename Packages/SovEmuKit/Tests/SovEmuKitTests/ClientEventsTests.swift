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

    @Test func eventsBecomeTheMutationsInput() {
        let event = ClientEvent(kind: .streamStalled, message: "no new picture", sessionId: nil, at: 2.5)
        let mutation = SovEmuAPI.report(client: "ios", events: [event])
        #expect(mutation.client == "ios")
        let input = mutation.events[0]
        #expect(input.kind.rawValue == "STREAM_STALLED" && input.message == "no new picture")
        // No session is an explicit null, as the schema's `sessionId: ID` takes it.
        #expect(input.sessionId == .null)
        #expect(input.at == .some(2.5))
    }
}
