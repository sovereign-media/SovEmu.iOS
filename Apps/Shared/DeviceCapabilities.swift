// What this device decodes and the screen it shows games on, read from WebRTC, VideoToolbox and
// UIKit into SovEmuKit's `Capabilities` document (SovEmu.Android's `WebRtc.capabilities`, over
// `LowLatencyVideoDecoderFactory`). Sent whole with every offer: without it the server always
// picks VP8, which libvpx decodes on the CPU and the player then copies to NV12.

import SovEmuKit
import UIKit
import VideoToolbox
import WebRTC

enum DeviceCapabilities {
    /// The document, read on the main thread (`UIScreen`).
    @MainActor
    static func document() -> ClientCapabilities {
        let decoders = RTCDefaultVideoDecoderFactory().supportedCodecs().map { decoder(for: $0.name) }
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
