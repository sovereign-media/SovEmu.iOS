import Foundation
import Testing
@testable import SovEmuKit

/// The same vectors as `input_layout_is_stable` in SovEmu.Protocol, protocol.test.ts and
/// SovEmu.Android's ProtocolTest.
struct ProtocolTests {
    @Test func encodesInputLikeTheRustReference() {
        let bytes = [UInt8](WireProtocol.encodeInput(seq: 0x0403_0201, clientTimeMs: 0x0807_0605, ports: [0x0a09]))
        #expect(bytes == [0x01, 1, 1, 2, 3, 4, 5, 6, 7, 8, 1, 0x09, 0x0a])
    }

    @Test func encodesHotkeysLikeTheRustReference() {
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: true, rewind: true)) == [0x02, 1, 0b11])
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: true, rewind: false)) == [0x02, 1, 0b01])
        #expect([UInt8](WireProtocol.encodeHotkeys(fastForward: false, rewind: true)) == [0x02, 1, 0b10])
    }

    @Test func encodesStatsLikeTheRustReference() {
        // `stats_are_json_after_the_header` in SovEmu.Protocol: only the known values, in order.
        let stats = WireProtocol.Stats(jitterMs: 1.5, fps: .nan, packetsLost: 2, framesDropped: 3)
        let expected = Data([0x04, 1]) + Data(#"{"jitter_ms":1.5,"packets_lost":2,"frames_dropped":3}"#.utf8)
        #expect(WireProtocol.encodeStats(stats) == expected)
        let named = WireProtocol.Stats(client: #"ios "pad""#, decodeMs: 4.04, fps: 60, kbps: 4999.96)
        #expect(String(decoding: WireProtocol.encodeStats(named).dropFirst(2), as: UTF8.self)
            == #"{"client":"ios \"pad\"","decode_ms":4,"fps":60,"kbps":5000}"#)
        // The path goes last, as `ClientStats` orders it.
        let path = WireProtocol.Stats(netRttMs: 24, decoder: "VideoToolbox", path: "relay-tcp")
        #expect(String(decoding: WireProtocol.encodeStats(path).dropFirst(2), as: UTF8.self)
            == #"{"net_rtt_ms":24,"decoder":"VideoToolbox","path":"relay-tcp"}"#)
    }

    @Test func statsComeFromTheChangeBetweenReadings() {
        var sampler = StatsSampler()
        let first = sampler.sample(StatsReading(at: 10, bytesReceived: 1000, totalDecodeTime: 1, framesDecoded: 100,
                                                framesPerSecond: 60, packetsLost: 1, framesDropped: 2))
        // The first reading has nothing to compare with.
        #expect(first == WireProtocol.Stats(fps: 60, packetsLost: 1, framesDropped: 2))
        let second = sampler.sample(
            StatsReading(at: 11, bytesReceived: 626_000, jitterBufferDelay: 0.6, jitterBufferEmittedCount: 60,
                         totalDecodeTime: 1.24, framesDecoded: 160, framesPerSecond: 60, width: 640, height: 480,
                         packetsLost: 1, framesDropped: 5, networkRttMs: 2.5, decoder: "VideoToolbox"),
            client: "ios")
        #expect(second.kbps == 5000)
        #expect(abs((second.decodeMs ?? 0) - 4) < 0.001)
        #expect(abs((second.jitterMs ?? 0) - 10) < 0.001)
        #expect(second.framesDropped == 5)
        #expect(second.client == "ios")
        #expect(second.decoder == "VideoToolbox")
    }

    @Test func encodesAnalogLikeTheRustReference() {
        // `analog_layout_is_stable_and_round_trips` in SovEmu.Protocol.
        let a = WireProtocol.Analog(lx: -32768, ly: 32767, rx: 1, ry: -2, l2: 0, r2: 0x1234)
        let bytes = [UInt8](WireProtocol.encodeAnalog(seq: 0x0403_0201, ports: [a]))
        #expect(bytes == [0x03, 1, 1, 2, 3, 4, 1, 0x00, 0x80, 0xff, 0x7f, 1, 0, 0xfe, 0xff, 0, 0, 0x34, 0x12])
        let clamped = [UInt8](WireProtocol.encodeAnalog(seq: 0, ports: [WireProtocol.Analog(lx: 40000)]))
        #expect(Array(clamped[7...8]) == [0xff, 0x7f])
        #expect(WireProtocol.Analog.stick(0.1) == 0)
        #expect(WireProtocol.Analog.stick(1) == 32767)
        #expect(WireProtocol.Analog.stick(-1) == -32767)
    }

    @Test func decodesTheRustReferenceAck() {
        let ack = WireProtocol.decodeAck(Data([0x81, 1, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]))
        #expect(ack == WireProtocol.Ack(seq: 1, clientTimeMs: 2, frame: 3))
    }

    @Test func rejectsOtherMessages() {
        #expect(WireProtocol.decodeAck(Data([0x81, 1])) == nil)
        #expect(WireProtocol.decodeAck(Data([0x01, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
        #expect(WireProtocol.decodeAck(Data([0x81, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
    }

    /// `PIPELINE_VECTOR` in SovEmu.Protocol, protocol.test.ts and SovEmu.Android's ProtocolTest.
    static let pipelineVector = #"{"renderer":"llvmpipe","renderer_software":true,"video":{"codec":"h264","encoder":"x264","hardware":false,"fallbacks":[{"encoder":"vaapi","reason":"no device"}],"width":256,"height":224,"fps":60.0,"kbps":3500,"limited_by":"client","estimate_kbps":4200},"audio":{"codec":"opus","source_hz":32040.0,"kbps":128},"run_ahead":1}"#

    private func pipelineMessage(_ json: String, type: UInt8 = 0x82, version: UInt8 = 1) -> Data {
        Data([type, version]) + Data(json.utf8)
    }

    @Test func decodesTheRustReferencePipeline() {
        let pipeline = WireProtocol.decodePipeline(pipelineMessage(Self.pipelineVector))
        #expect(pipeline == WireProtocol.Pipeline(
            renderer: "llvmpipe", rendererSoftware: true,
            video: .init(codec: "h264", encoder: "x264", hardware: false,
                         fallbacks: [.init(encoder: "vaapi", reason: "no device")], width: 256, height: 224, fps: 60,
                         kbps: 3500, limitedBy: "client", estimateKbps: 4200),
            audio: .init(codec: "opus", sourceHz: 32040, kbps: 128),
            runAhead: 1))
    }

    @Test func aPipelineToleratesMissingAndUnknownKeys() throws {
        let sparse = try #require(WireProtocol.decodePipeline(
            pipelineMessage(#"{"video":{"codec":"vp8","newer":1},"later":true}"#)))
        #expect(sparse.video.codec == "vp8")
        #expect(sparse.renderer == nil)
        #expect(sparse.video.fallbacks.isEmpty)
        #expect(sparse.audio == WireProtocol.Pipeline.Audio())
        #expect(WireProtocol.decodePipeline(pipelineMessage("{}")) == WireProtocol.Pipeline())
    }

    @Test func aChangeInQualityIsSaidWithWhyItFell() {
        func at(_ kbps: Int, _ limitedBy: String = "") -> WireProtocol.Pipeline {
            WireProtocol.Pipeline(video: .init(codec: "vp8", kbps: kbps, limitedBy: limitedBy))
        }
        typealias Notice = WireProtocol.QualityNotice
        #expect(WireProtocol.qualityNotice(before: at(5000), now: at(8400))
            == Notice(line: "Connection improved. Playing at a higher quality.", icon: "wifi-up"))
        #expect(WireProtocol.qualityNotice(before: at(5000), now: at(3300, "connection"))
            == Notice(line: "Slow connection. Playing at a lower quality.", icon: "wifi-alert"))
        #expect(WireProtocol.qualityNotice(before: at(5000), now: at(800, "client"))
            == Notice(line: "This device is falling behind. Playing at a lower quality.", icon: "gauge"))
        // Up again after the device fell behind: the connection did not improve.
        #expect(WireProtocol.qualityNotice(before: at(800, "client"), now: at(5000))
            == Notice(line: "Playing at a higher quality.", icon: "gauge"))
        // The first message, an unchanged one, and a server that does not tell say nothing.
        #expect(WireProtocol.qualityNotice(before: nil, now: at(5000)) == nil)
        #expect(WireProtocol.qualityNotice(before: at(5000), now: at(5000)) == nil)
        #expect(WireProtocol.qualityNotice(before: at(0), now: at(5000)) == nil)
        #expect(WireProtocol.qualityNotice(before: at(5000), now: at(0)) == nil)
    }

    @Test func rejectsOtherPipelineMessages() {
        #expect(WireProtocol.decodePipeline(pipelineMessage(#""fast""#)) == nil)
        #expect(WireProtocol.decodePipeline(pipelineMessage("[]")) == nil)
        #expect(WireProtocol.decodePipeline(pipelineMessage("{}", type: 0x04)) == nil)
        #expect(WireProtocol.decodePipeline(pipelineMessage("{}", version: 2)) == nil)
        #expect(WireProtocol.decodePipeline(Data([0x82])) == nil)
        #expect(WireProtocol.decodePipeline(Data([0x81, 1, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0])) == nil)
        let long = #"{"renderer":""# + String(repeating: "x", count: 4096) + #""}"#
        #expect(WireProtocol.decodePipeline(pipelineMessage(long)) == nil)
        // An ack is not a pipeline, nor a pipeline an ack.
        #expect(WireProtocol.decodeAck(pipelineMessage(Self.pipelineVector)) == nil)
    }

    /// `LINK_VECTOR` in SovEmu.Protocol, protocol.test.ts and SovEmu.Android's ProtocolTest.
    static let linkVector = #"{"state":"done","elapsed_ms":640,"budget_ms":2000,"path":"relay-udp","estimate_kbps":18200,"start_kbps":12000,"rtt_ms":24.5,"stopped_by":"ceiling"}"#

    @Test func decodesTheRustReferenceLink() {
        #expect(WireProtocol.decodeLink(pipelineMessage(Self.linkVector, type: 0x83)) == WireProtocol.Link(
            state: "done", elapsedMs: 640, budgetMs: 2000, path: "relay-udp", estimateKbps: 18200, startKbps: 12000,
            rttMs: 24.5, stoppedBy: "ceiling"))
    }

    @Test func readsACheckStillRunningAndRefusesAnythingElse() throws {
        // While probing the worker has no result yet: the app must still read the progress.
        let probing = try #require(WireProtocol.decodeLink(
            pipelineMessage(#"{"state":"probing","elapsed_ms":100,"newer":1}"#, type: 0x83)))
        #expect(probing == WireProtocol.Link(state: "probing", elapsedMs: 100))
        #expect(probing.rttMs == nil && probing.path == "")
        #expect(WireProtocol.decodeLink(pipelineMessage("[1]", type: 0x83)) == nil)
        #expect(WireProtocol.decodeLink(pipelineMessage("{}", type: 0x82)) == nil)
        #expect(WireProtocol.decodeLink(pipelineMessage("{}", type: 0x83, version: 2)) == nil)
        let long = pipelineMessage(String(repeating: " ", count: WireProtocol.maxLinkLength) + "{}", type: 0x83)
        #expect(WireProtocol.decodeLink(long) == nil)
        // A pipeline is not a link, nor a link a pipeline.
        #expect(WireProtocol.decodeLink(pipelineMessage(Self.pipelineVector)) == nil)
        #expect(WireProtocol.decodePipeline(pipelineMessage(Self.linkVector, type: 0x83)) == nil)
    }

    @Test func aPipelineCarriesTheCheckOnceDone() throws {
        // The result comes again with every pipeline: a lost `0x83` still fills the overlay.
        let pipeline = try #require(WireProtocol.decodePipeline(
            pipelineMessage(#"{"video":{"estimate_kbps":15400},"link":"# + Self.linkVector + "}")))
        #expect(pipeline.video.estimateKbps == 15400)
        #expect(pipeline.link?.startKbps == 12000)
        #expect(WireProtocol.decodePipeline(pipelineMessage(Self.pipelineVector))?.link == nil)
    }

    @Test func capsPortsAndNumbersButtonsLikeLibretro() {
        #expect(WireProtocol.encodeInput(seq: 1, clientTimeMs: 0, ports: [1, 2, 3, 4, 5]).count == 19)
        #expect(RetroButton.b.bit == 1)
        #expect(RetroButton.start.bit == 1 << 3)
        #expect(RetroButton.a.bit == 1 << 8)
    }
}
