import Testing
@testable import SovEmuKit

/// The same cases as SovEmu.Android's CapabilitiesTest: without a whole, well-formed document the
/// server picks VP8, decoded on the CPU.
struct CapabilitiesTests {
    private let screen = ScreenMode(width: 3840, height: 2160, refreshHz: 59.94)

    /// A Mi TV (Amlogic S7D): every codec but VP8 in hardware, with a low-latency mode.
    private let miTv = [
        DecoderChoice(codec: "VP8", hardware: false, lowLatency: false, name: "c2.amlogic.vp8.decoder.sw"),
        DecoderChoice(codec: "VP9", hardware: true, lowLatency: true, name: "c2.amlogic.vp9.decoder"),
        DecoderChoice(codec: "H264", hardware: true, lowLatency: true, name: "c2.amlogic.avc.decoder"),
        DecoderChoice(codec: "AV1", hardware: true, lowLatency: true, name: "c2.amlogic.av1.decoder"),
    ]

    @Test func theDocumentIsWholeAndOfThisVersion() throws {
        let document = Capabilities.document(miTv, screen: screen)
        #expect(document.version == 1)
        #expect(document.videoDecoders.map(\.codec) == [.vp8, .vp9, .h264, .av1])
        let h264 = document.videoDecoders[2]
        #expect(h264.hardware && h264.lowLatency)
        #expect(h264.name == "c2.amlogic.avc.decoder")
        #expect(document.display == screen)
        #expect(Capabilities.summary(document)
            == "vp8 software, vp9 hardware low-latency, h264 hardware low-latency, av1 hardware low-latency")
    }

    @Test func eachCodecHasOneRowAndUnknownCodecsAreLeftOut() {
        // WebRTC lists H.264 once per profile, and may list codecs the server has no name for.
        let decoders = [
            DecoderChoice(codec: "H264", hardware: true, lowLatency: true, name: "c2.vendor.avc.decoder"),
            DecoderChoice(codec: "H264", hardware: false, lowLatency: false, name: "another"),
            DecoderChoice(codec: "h265", hardware: true, lowLatency: false, name: nil),
            DecoderChoice(codec: "VP10", hardware: true, lowLatency: true, name: "c2.vendor.vp10"),
        ]
        let rows = Capabilities.document(decoders, screen: screen).videoDecoders
        #expect(rows.map(\.codec) == [.h264, .h265])
        #expect(rows[0].name == "c2.vendor.avc.decoder")
        #expect(rows[1].name == nil)
        #expect(Capabilities.codec("VP10") == nil)
    }

    @Test func decoderNamesAreKeptShort() {
        let long = DecoderChoice(codec: "VP8", hardware: false, lowLatency: true, name: "  " + String(repeating: "x", count: 200))
        let blank = DecoderChoice(codec: "VP9", hardware: false, lowLatency: true, name: "   ")
        let rows = Capabilities.document([long, blank], screen: screen).videoDecoders
        #expect(rows[0].name == String(repeating: "x", count: 80))
        #expect(rows[1].name == nil)
    }
}
