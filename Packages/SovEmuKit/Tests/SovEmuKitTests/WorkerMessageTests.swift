import Foundation
import Testing
@testable import SovEmuKit

/// The worker's messages, read by their first byte, and the input round trips their acks give.
struct WorkerMessageTests {
    /// Seq 7, client time 1000, frame 42: SovEmu.Android's `RecentRttsTest` vector.
    private static let ack: [UInt8] = [0x81, 1, 7, 0, 0, 0, 0xe8, 3, 0, 0, 42, 0, 0, 0]

    @Test func anAckIsReadInPlace() {
        let expected = WireProtocol.WorkerMessage.ack(WireProtocol.Ack(seq: 7, clientTimeMs: 1000, frame: 42))
        #expect(WireProtocol.decodeWorkerMessage(Data(Self.ack)) == expected)
        // A slice that does not start at index 0 (a buffer read part way) reads the same.
        let slice = Data([9, 9] + Self.ack).dropFirst(2)
        #expect(WireProtocol.decodeWorkerMessage(slice) == expected)
        #expect(WireProtocol.decodeAck(Data(Self.ack))?.clientTimeMs == 1000, "the same as the old decoder")
    }

    @Test func thePipelineAndTheLinkGoToTheirOwnDecoders() {
        let pipeline = Data([0x82, 1]) + Data(ProtocolTests.pipelineVector.utf8)
        #expect(WireProtocol.decodeWorkerMessage(pipeline) == WireProtocol.decodePipeline(pipeline).map { .pipeline($0) })
        let link = Data([0x83, 1]) + Data(ProtocolTests.linkVector.utf8)
        #expect(WireProtocol.decodeWorkerMessage(link) == WireProtocol.decodeLink(link).map { .link($0) })
    }

    @Test func aNewerWorkersMessageIsUnknownNotMistakenForAnother() {
        // A type this app does not know, and a known type in a version it does not: neither may
        // be read as what it resembles.
        #expect(WireProtocol.decodeWorkerMessage(Data([0x84, 1, 0, 0])) == .unknown(type: 0x84, version: 1))
        #expect(WireProtocol.decodeWorkerMessage(Data([0x81, 2] + Self.ack.dropFirst(2))) == .unknown(type: 0x81, version: 2))
    }

    @Test func aMessageCutShortOrOfTheWrongShapeIsMalformed() {
        #expect(WireProtocol.decodeWorkerMessage(Data(Self.ack.prefix(13))) == .malformed(type: 0x81))
        #expect(WireProtocol.decodeWorkerMessage(Data([0x82, 1]) + Data("[]".utf8)) == .malformed(type: 0x82))
        #expect(WireProtocol.decodeWorkerMessage(Data([0x83])) == .malformed(type: 0x83))
        #expect(WireProtocol.decodeWorkerMessage(Data()) == .malformed(type: 0))
    }

    @Test func unknownKindsAreCountedAndEachSaidOnce() {
        let unknown = UnknownMessages()
        #expect(unknown.add(type: 0x84, version: 1), "the first of a kind is logged")
        #expect(!unknown.add(type: 0x84, version: 1), "a repeat, every frame perhaps, is not")
        #expect(unknown.add(type: 0x81, version: 2), "another version is another kind")
        #expect(unknown.total == 3)
        #expect(unknown.kinds() == [
            UnknownMessages.Kind(type: 0x81, version: 2, count: 1),
            UnknownMessages.Kind(type: 0x84, version: 1, count: 2),
        ])
    }

    // MARK: - RecentRtts, as SovEmu.Android's RecentRttsTest

    @Test func keepsTheMostRecentOldestFirst() {
        let rtts = RecentRtts(capacity: 3)
        #expect(rtts.values() == [])
        for ms in Int64(1)...5 { rtts.add(ms) }
        #expect(rtts.values() == [3, 4, 5])
    }

    @Test func theWindowIsTheOtherClients() {
        // The worker compares every client's median and p95: over 32 (as this app had) a burst
        // of slow acks weighed twice what it does on the web and Android.
        #expect(RecentRtts.defaultCapacity == 60)
        let rtts = RecentRtts()
        for ms in Int64(1)...100 { rtts.add(ms) }
        #expect(rtts.values() == Array(41...100))
    }
}
