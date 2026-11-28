// What this device decodes and the screen it shows games on, read from WebRTC, VideoToolbox and
// UIKit into SovEmuKit's `Capabilities` document (SovEmu.Android's `WebRtc.capabilities`, over
// `LowLatencyVideoDecoderFactory`). Sent whole with every offer.

import SovEmuKit
import UIKit
import VideoToolbox
import WebRTC

enum DeviceCapabilities {
    /// The codecs this app declares, of those WebRTC decodes: VP8 only for now. It keeps up in
    /// real time, while H.264 from a server without a GPU (x264) held frames back and was not
    /// playable; declaring only VP8 keeps the server's `auto` from choosing H.264 for this app.
    /// Add a codec here once it has been measured on a device.
    private static let declared: Set<String> = ["VP8"]

    /// The document, read on the main thread (`UIScreen`).
    @MainActor
    static func document() -> ClientCapabilities {
        let decoders = RTCDefaultVideoDecoderFactory().supportedCodecs()
            .filter { declared.contains($0.name.uppercased()) }
            .map { decoder(for: $0.name) }
        return Capabilities.document(decoders, screen: screen())
    }

    /// The decoder WebRTC's default factory makes for each codec it lists. H.264 and H.265 go to
    /// VideoToolbox, in hardware where the device has it; WebRTC streams have no B-frames, so it
    /// hands each frame on as it is decoded. VP8 and VP9 are libvpx and AV1 dav1d, on the CPU,
    /// also frame by frame.
    private static func decoder(for name: String) -> DecoderChoice {
        switch name.uppercased() {
        case "H264":
            DecoderChoice(codec: name, hardware: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264),
                          lowLatency: true, name: "VideoToolbox")
        case "H265":
            DecoderChoice(codec: name, hardware: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
                          lowLatency: true, name: "VideoToolbox")
        case "AV1":
            DecoderChoice(codec: name, hardware: false, lowLatency: true, name: "dav1d")
        default:
            DecoderChoice(codec: name, hardware: false, lowLatency: true, name: "libvpx")
        }
    }

    /// The screen in physical pixels, landscape (games are played across it), and its refresh.
    @MainActor
    private static func screen() -> ScreenMode {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let screen = scene?.screen
        let pixels = screen?.nativeBounds.size ?? .zero
        return ScreenMode(width: Int(max(pixels.width, pixels.height)), height: Int(min(pixels.width, pixels.height)),
                          refreshHz: Double(screen?.maximumFramesPerSecond ?? 60))
    }
}
