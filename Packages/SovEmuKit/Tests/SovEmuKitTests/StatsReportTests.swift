import Foundation
import Testing
@testable import SovEmuKit

/// Reading WebRTC's stats report: fixtures shaped as LiveKit's iOS build reports them (the ids,
/// types and keys of `RTCStatisticsReport`), decoded from JSON so the values are the
/// `NSNumber`s and `NSString`s the app is handed.
struct StatsReportTests {
    /// Playing through the relay over TCP: the transport names the selected pair.
    static let playing = #"""
    {
      "T01": {"type": "transport", "selectedCandidatePairId": "CPa_b", "dtlsState": "connected"},
      "CPa_b": {"type": "candidate-pair", "state": "succeeded", "nominated": true,
                "currentRoundTripTime": 0.0234, "localCandidateId": "Ia", "remoteCandidateId": "Ib"},
      "CPc_d": {"type": "candidate-pair", "state": "succeeded", "nominated": true,
                "currentRoundTripTime": 0.5, "localCandidateId": "Ic", "remoteCandidateId": "Id"},
      "Ia": {"type": "local-candidate", "candidateType": "relay", "protocol": "udp", "relayProtocol": "tcp"},
      "Ib": {"type": "remote-candidate", "candidateType": "host", "protocol": "udp"},
      "Ic": {"type": "local-candidate", "candidateType": "host", "protocol": "udp"},
      "Id": {"type": "remote-candidate", "candidateType": "host", "protocol": "udp"},
      "IT01V": {"type": "inbound-rtp", "kind": "video", "bytesReceived": 1250000, "jitterBufferDelay": 2.4,
                "jitterBufferEmittedCount": 120, "totalDecodeTime": 0.36, "framesDecoded": 120,
                "framesPerSecond": 60, "frameWidth": 256, "frameHeight": 224, "packetsLost": -2,
                "framesDropped": 1, "decoderImplementation": "libvpx"},
      "IT01A": {"type": "inbound-rtp", "kind": "audio", "packetsLost": 3, "jitterBufferDelay": 4.8,
                "jitterBufferTargetDelay": 3.6, "jitterBufferEmittedCount": 96000},
      "AP": {"type": "media-playout", "kind": "audio", "totalPlayoutDelay": 960, "totalSamplesCount": 96000}
    }
    """#

    /// While the worker checks the connection: no video yet, no audio, a nominated pair but no
    /// transport naming it.
    static let probing = #"""
    {
      "CPa_b": {"type": "candidate-pair", "state": "in-progress", "nominated": false,
                "currentRoundTripTime": 0.9, "localCandidateId": "Ia", "remoteCandidateId": "Ib"},
      "CPc_d": {"type": "candidate-pair", "state": "succeeded", "nominated": true,
                "currentRoundTripTime": 0.012, "localCandidateId": "Ic", "remoteCandidateId": "Id"},
      "Ia": {"type": "local-candidate", "candidateType": "relay", "protocol": "udp"},
      "Ib": {"type": "remote-candidate", "candidateType": "host", "protocol": "udp"},
      "Ic": {"type": "local-candidate", "candidateType": "srflx", "protocol": "udp"},
      "Id": {"type": "remote-candidate", "candidateType": "host", "protocol": "udp"}
    }
    """#

    static func entries(_ json: String) throws -> [String: StatsEntry] {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]])
        return object.mapValues { StatsEntry(type: $0["type"] as? String ?? "", values: $0) }
    }

    @Test func aPlayingReportReadsEveryCounterAndTheSelectedPair() throws {
        let r = StatsReading(report: try Self.entries(Self.playing), timestampUs: 12_500_000)
        #expect(r.at == 12.5)
        #expect(r.hasVideo)
        #expect([r.bytesReceived, r.jitterBufferDelay, r.jitterBufferEmittedCount, r.totalDecodeTime, r.framesDecoded]
            == [1_250_000, 2.4, 120, 0.36, 120])
        #expect(r.framesPerSecond == 60 && r.width == 256 && r.height == 224)
        #expect(r.framesDropped == 1 && r.decoder == "libvpx")
        // The video's -2 (duplicates) counts as none, the audio's 3 as lost.
        #expect(r.packetsLost == 3)
        // The transport's pair, not the other nominated one with its 500 ms.
        #expect(abs((r.networkRttMs ?? 0) - 23.4) < 1e-9)
        #expect(r.local == IceCandidateStats(candidateType: "relay", protocol: "udp", relayProtocol: "tcp"))
        #expect(r.remote == IceCandidateStats(candidateType: "host", protocol: "udp"))
        #expect([r.audioJitterBufferDelay, r.audioJitterBufferTargetDelay, r.audioJitterBufferEmittedCount]
            == [4.8, 3.6, 96000])
        #expect([r.audioPlayoutDelay, r.audioPlayoutSamples] == [960, 96000])
    }

    @Test func beforeTheFirstFrameOnlyThePathIsRead() throws {
        let r = StatsReading(report: try Self.entries(Self.probing), timestampUs: 1_000_000)
        #expect(!r.hasVideo, "the worker sends no video while it checks the connection")
        #expect(r.bytesReceived == 0 && r.framesPerSecond == nil && r.decoder == nil && r.packetsLost == 0)
        // No transport names a pair: the nominated one that succeeded, not the one in progress.
        #expect(abs((r.networkRttMs ?? 0) - 12) < 1e-9)
        #expect(r.local?.candidateType == "srflx")
        #expect(LinkLabels.clientPath(r.local) == "direct")
    }

    @Test func anEmptyReportKnowsNothing() {
        let r = StatsReading(report: [:], timestampUs: 0)
        #expect(r == StatsReading(at: 0, hasVideo: false))
    }

    @Test func valuesOfAnotherTypeReadAsUnknown() {
        // A newer WebRTC might report a key as a string, or a pair id that is not in the report.
        let entries = [
            "V": StatsEntry(type: "inbound-rtp", values: ["kind": "video", "framesPerSecond": "60", "frameWidth": 320]),
            "T": StatsEntry(type: "transport", values: ["selectedCandidatePairId": "missing"]),
        ]
        let r = StatsReading(report: entries, timestampUs: 0)
        #expect(r.framesPerSecond == nil && r.width == 320)
        #expect(r.networkRttMs == nil && r.local == nil)
    }

    @Test func twoReadingsMakeTheStatsTheWorkerIsSent() throws {
        // From the fixture a second apart: the per-second rates come from the change.
        let first = StatsReading(report: try Self.entries(Self.playing), timestampUs: 1_000_000)
        var later = first
        later.at = 2
        later.bytesReceived += 125_000
        later.totalDecodeTime += 0.18
        later.framesDecoded += 60
        var sampler = StatsSampler()
        _ = sampler.sample(first)
        let stats = sampler.sample(later, inputRtts: [20, 30, 40])
        #expect(stats.kbps == 1000)
        #expect(abs((stats.decodeMs ?? 0) - 3) < 1e-9)
        #expect(stats.path == "relay-tcp")
        #expect(stats.inputRttP50Ms == 30)
    }
}
