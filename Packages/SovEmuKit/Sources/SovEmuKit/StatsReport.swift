import Foundation

// Reading a peer connection's stats report, as SovEmu.Android's `Stream.reading` and the web's
// stats sampler: the inbound video and audio, the audio output, and the selected candidate pair
// with both its ends. Here, not in the app, so a captured report is a test fixture.

/// One entry of WebRTC's stats report (`RTCStatistics`): its `type` and its values, which are
/// `NSNumber`s and `NSString`s as WebRTC hands them over (or as JSON decodes them).
public struct StatsEntry {
    public let type: String
    public let values: [String: Any]

    public init(type: String, values: [String: Any]) {
        (self.type, self.values) = (type, values)
    }
}

extension StatsReading {
    /// The reading in a report: `entries` by id, taken at `timestampUs` (microseconds, on a
    /// clock that only moves forward). What a report lacks reads as zero or unknown: before the
    /// first frame there is no inbound video, and before ICE has chosen no pair.
    public init(report entries: [String: StatsEntry], timestampUs: Double) {
        let all = entries.values
        func inbound(_ kind: String) -> [String: Any] {
            all.first { $0.type == "inbound-rtp" && $0.values["kind"] as? String == kind }?.values ?? [:]
        }
        let video = inbound("video")
        let audio = inbound("audio")
        let playout = all.first { $0.type == "media-playout" }?.values ?? [:]
        // The transport's selected pair, as the web's `selectedPair`; else the nominated one
        // that succeeded (a report without the transport's link to it).
        let selectedId = all.lazy.compactMap { $0.type == "transport" ? $0.values["selectedCandidatePairId"] as? String : nil }.first
        let pair = selectedId.flatMap { entries[$0]?.values } ?? all.first {
            $0.type == "candidate-pair" && Self.bool($0.values, "nominated") && $0.values["state"] as? String == "succeeded"
        }?.values ?? [:]
        func candidate(_ key: String) -> IceCandidateStats? {
            guard let id = pair[key] as? String, let values = entries[id]?.values,
                  let type = values["candidateType"] as? String else { return nil }
            return IceCandidateStats(candidateType: type, protocol: values["protocol"] as? String,
                                     relayProtocol: values["relayProtocol"] as? String)
        }
        let num = Self.number
        self.init(
            at: timestampUs / 1_000_000,
            bytesReceived: num(video, "bytesReceived") ?? 0,
            jitterBufferDelay: num(video, "jitterBufferDelay") ?? 0,
            jitterBufferEmittedCount: num(video, "jitterBufferEmittedCount") ?? 0,
            totalDecodeTime: num(video, "totalDecodeTime") ?? 0,
            framesDecoded: num(video, "framesDecoded") ?? 0,
            framesPerSecond: num(video, "framesPerSecond"),
            width: num(video, "frameWidth").map { Int($0) },
            height: num(video, "frameHeight").map { Int($0) },
            packetsLost: Self.packetsLost(video: num(video, "packetsLost"), audio: num(audio, "packetsLost")),
            framesDropped: num(video, "framesDropped").map { Int($0) },
            networkRttMs: num(pair, "currentRoundTripTime").map { $0 * 1000 },
            decoder: video["decoderImplementation"] as? String,
            hasVideo: !video.isEmpty,
            local: candidate("localCandidateId"),
            remote: candidate("remoteCandidateId"))
        audioJitterBufferDelay = num(audio, "jitterBufferDelay") ?? 0
        audioJitterBufferTargetDelay = num(audio, "jitterBufferTargetDelay") ?? 0
        audioJitterBufferEmittedCount = num(audio, "jitterBufferEmittedCount") ?? 0
        audioPlayoutDelay = num(playout, "totalPlayoutDelay") ?? 0
        audioPlayoutSamples = num(playout, "totalSamplesCount") ?? 0
    }

    /// A finite number, or nil: a value WebRTC leaves out, or one of another type.
    private static func number(_ values: [String: Any], _ key: String) -> Double? {
        guard let n = values[key] as? NSNumber else { return nil }
        let x = n.doubleValue
        return x.isFinite ? x : nil
    }

    private static func bool(_ values: [String: Any], _ key: String) -> Bool {
        (values[key] as? NSNumber)?.boolValue ?? false
    }
}
