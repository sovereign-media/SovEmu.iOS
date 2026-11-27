import Foundation
import Testing
@testable import SovEmuKit

/// The same cases as SovEmu.Web's link.test.ts, and the path cases of its stats.test.ts.
struct LinkTests {
    private let host = IceCandidateStats(candidateType: "host", protocol: "udp")
    private func relay(_ relayProtocol: String?) -> IceCandidateStats {
        IceCandidateStats(candidateType: "relay", protocol: "udp", relayProtocol: relayProtocol)
    }

    private func done(stoppedBy: String = "ceiling", estimateKbps: Int = 18200, state: String = "done") -> WireProtocol.Link {
        WireProtocol.Link(state: state, elapsedMs: 640, budgetMs: 2000, path: "relay-udp", estimateKbps: estimateKbps,
                          startKbps: 12000, rttMs: 24.5, stoppedBy: stoppedBy)
    }

    @Test func thePathSaysWhichOfTheRelaysTransportsItUsesWhichOnlyTheAppCanTell() {
        // The relay forwards UDP to the worker whatever the client used: without this the worker
        // could not start a TCP-relayed player lower, as it must.
        #expect(LinkLabels.clientPath(relay("tcp")) == "relay-tcp")
        #expect(LinkLabels.clientPath(relay("tls")) == "relay-tls")
        #expect(LinkLabels.clientPath(relay("udp")) == "relay-udp")
        #expect(LinkLabels.clientPath(relay(nil)) == "relay-udp")
        #expect(LinkLabels.clientPath(host) == "direct")
        #expect(LinkLabels.clientPath(IceCandidateStats(candidateType: "srflx")) == "direct")
        #expect(LinkLabels.clientPath(nil) == nil)
    }

    @Test func theNetworkRowsNameThePairTheTransportAndTheNetwork() {
        #expect(LinkLabels.pairLabel(IceCandidateStats(candidateType: "srflx"), host) == "STUN → host")
        #expect(LinkLabels.pairLabel(relay("udp"), host) == "relay → host")
        #expect(LinkLabels.transportLabel(relay("tcp")) == "TCP to the relay")
        #expect(LinkLabels.transportLabel(host) == "UDP")
        // The loading screen says only where the player is; the details are in the overlay.
        #expect(LinkLabels.networkLabel("lan") == "Home network")
        #expect(LinkLabels.networkLabel("relay-tcp") == "Remote")
        #expect(LinkLabels.networkLabel("") == nil)
        #expect(LinkLabels.rateLabel(18200) == "18.2 Mbit/s")
        #expect(LinkLabels.rateLabel(850) == "850 kbit/s")
    }

    @Test func itSaysWhatWasMeasuredAtTheStartAndWhenNothingWas() {
        #expect(LinkLabels.measuredLabel(done()) == "18.2 Mbit/s in 0.6 s (reached the ceiling)")
        #expect(LinkLabels.measuredLabel(done(stoppedBy: "off", estimateKbps: 0)) == "not measured (turned off)")
        #expect(LinkLabels.measuredLabel(nil) == "not measured")
        #expect(LinkLabels.measuredLabel(done(state: "probing")) == "not measured")
    }

    @Test func theAppsOwnRowsShowEvenWithAnOlderWorker() {
        // TURN server, transport and path come from WebRTC's statistics: an older worker, or the
        // check turned off, must not hide them.
        let rows = WireProtocol.networkRows(local: relay("tcp"), remote: host, link: nil, estimateKbps: 0)
        #expect(rows.map { "\($0.label): \($0.value)" } == [
            "TURN server: Yes", "Transport: TCP to the relay", "Path: relay → host", "Measured at start: not measured",
        ])
        let full = WireProtocol.networkRows(local: relay("udp"), remote: host, link: done(), estimateKbps: 15400)
        #expect(full.first.map { "\($0.label): \($0.value)" } == "Network: Remote")
        #expect(full.suffix(2).map { "\($0.label): \($0.value)" } == ["Started at: 12.0 Mbit/s", "Estimate now: 15.4 Mbit/s"])
    }

    @Test func beforeTheFirstFrameTheWorkerIsSentThePathAndRoundTripItChecksTheLinkWith() {
        // #243: the worker sends no video while it checks the connection, and needs to know the
        // relay's transport (only this app can tell) and whether the round trip rises.
        var sampler = StatsSampler()
        let reading = StatsReading(at: 1, networkRttMs: 24, hasVideo: false, local: relay("tcp"), remote: host)
        let stats = sampler.sample(reading, client: "ios", inputRtts: [10])
        #expect(stats == WireProtocol.Stats(client: "ios", netRttMs: 24, path: "relay-tcp"))
        let rows = WireProtocol.overlayRows(stats, reading: reading, pipeline: nil, link: nil)
        #expect(rows.map(\.label) == ["TURN server", "Transport", "Path", "Measured at start"])
    }

    @Test func thereIsNothingToSayBeforeICEHasChosenAPair() {
        var sampler = StatsSampler()
        let reading = StatsReading(at: 1, hasVideo: false)
        let stats = sampler.sample(reading)
        #expect(stats.path == nil)
        #expect(WireProtocol.overlayRows(stats, reading: reading, pipeline: nil, link: nil).map { "\($0.label): \($0.value)" }
            == ["Measured at start: not measured"])
    }

    @Test func onceThereIsVideoTheNetworkRowsFollowTheStreamsAndCarryThePath() {
        var sampler = StatsSampler()
        let reading = StatsReading(at: 1, framesPerSecond: 60, local: host, remote: host)
        let stats = sampler.sample(reading)
        #expect(stats.path == "direct")
        let pipeline = WireProtocol.Pipeline(video: .init(codec: "h264", estimateKbps: 15400))
        let rows = WireProtocol.overlayRows(stats, reading: reading, pipeline: pipeline, link: done())
        #expect(rows.first?.label == "Estimated button→pixel")
        #expect(rows.contains { $0.label == "Stream" })
        #expect(rows.last.map { "\($0.label): \($0.value)" } == "Estimate now: 15.4 Mbit/s")
    }
}
