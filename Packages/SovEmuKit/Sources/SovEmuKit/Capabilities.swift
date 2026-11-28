import Foundation

// What this device can decode and show, sent with every offer (`sessionOffer`'s `capabilities`),
// as SovEmu.Android's Capabilities.kt (same names and test cases). The server keeps it against
// this sign-in and picks each session's codec from it: with none it always picks VP8, which an
// iPhone or Apple TV decodes in software.

/// The decoder this device would use for one of WebRTC's codecs (`codec`: its name there, `VP8`,
/// `H264`…): whether the device's `hardware` decodes it, whether it hands over each frame as soon
/// as it is decoded (`lowLatency`), and the decoder's own `name` (`VideoToolbox`, `libvpx`).
public struct DecoderChoice: Equatable, Sendable {
    public var codec: String
    public var hardware: Bool
    public var lowLatency: Bool
    public var name: String?

    public init(codec: String, hardware: Bool, lowLatency: Bool, name: String?) {
        (self.codec, self.hardware, self.lowLatency, self.name) = (codec, hardware, lowLatency, name)
    }
}

/// The screen games are shown on: physical pixels, and pictures a second.
public struct ScreenMode: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var refreshHz: Double

    public init(width: Int, height: Int, refreshHz: Double) {
        (self.width, self.height, self.refreshHz) = (width, height, refreshHz)
    }
}

/// The server's names for the codecs it knows (`VideoCodec` in its schema).
public enum VideoCodecName: String, Equatable, Sendable {
    case vp8 = "VP8", h264 = "H264", vp9 = "VP9", av1 = "AV1", h265 = "H265"
}

/// One codec's row in the document.
public struct VideoDecoderRow: Equatable, Sendable {
    public var codec: VideoCodecName
    public var hardware: Bool
    public var lowLatency: Bool
    public var name: String?
}

/// The whole document, of `Capabilities.version`.
public struct ClientCapabilities: Equatable, Sendable {
    public var version: Int
    public var videoDecoders: [VideoDecoderRow]
    public var display: ScreenMode
}

public enum Capabilities {
    /// The document's shape. The server refuses any other, asking the player to update.
    public static let version = 1

    /// Longest decoder name the server keeps.
    private static let maxName = 80

    /// The document for `decoders` and `screen`. A codec the server has no name for is left out,
    /// and a codec listed more than once (WebRTC lists H.264 once per profile) keeps its first
    /// row: the server takes one decoder for each codec.
    public static func document(_ decoders: [DecoderChoice], screen: ScreenMode) -> ClientCapabilities {
        var rows: [VideoDecoderRow] = []
        for decoder in decoders {
            guard let codec = codec(decoder.codec), !rows.contains(where: { $0.codec == codec }) else { continue }
            let name = decoder.name.map { String($0.trimmingCharacters(in: .whitespaces).prefix(maxName)) }
            rows.append(VideoDecoderRow(codec: codec, hardware: decoder.hardware, lowLatency: decoder.lowLatency,
                                        name: name?.isEmpty == false ? name : nil))
        }
        return ClientCapabilities(version: version, videoDecoders: rows, display: screen)
    }

    /// The server's name for one of WebRTC's codec names; nil for one it does not know.
    public static func codec(_ webRtcName: String) -> VideoCodecName? {
        VideoCodecName(rawValue: webRtcName.uppercased())
    }

    /// The document in a line, for the log: `vp8 software, h264 hardware low-latency`.
    public static func summary(_ document: ClientCapabilities) -> String {
        document.videoDecoders.map {
            "\($0.codec.rawValue.lowercased()) \($0.hardware ? "hardware" : "software")\($0.lowLatency ? " low-latency" : "")"
        }.joined(separator: ", ")
    }
}

extension ClientCapabilities {
    var input: SovEmuGraphQL.ClientCapabilitiesInput {
        SovEmuGraphQL.ClientCapabilitiesInput(
            version: Int32(version),
            videoDecoders: videoDecoders.map {
                SovEmuGraphQL.VideoDecoderInput(
                    codec: .init(rawValue: $0.codec.rawValue), hardware: $0.hardware, lowLatency: $0.lowLatency,
                    name: .orNull($0.name))
            },
            display: SovEmuGraphQL.DisplayInput(
                width: int32(display.width), height: int32(display.height), refreshHz: display.refreshHz))
    }
}
