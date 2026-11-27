// The game's picture, drawn by AVFoundation's sample-buffer layer rather than WebRTC's Metal view
// (`RTCMTLVideoView` drew nothing on an Apple TV, nor in the simulators, with LiveKit's build).
// Each decoded frame becomes a pixel buffer: a hardware decoder's own, or a software decoder's
// I420 planes copied into an NV12 one, and is shown at once (no timing of its own: the stream
// is already paced). The picture is stretched to the view, which the player shapes to the
// console's: never cropped. SovEmu.Android's `StreamView` and its `SharpDrawer`.
import AVFoundation
import CoreVideo
import UIKit
import WebRTC

final class SampleBufferVideoView: UIView, RTCVideoRenderer, @unchecked Sendable {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var display: AVSampleBufferDisplayLayer {
        // A `layerClass` override makes the layer this type.
        layer as! AVSampleBufferDisplayLayer
    }

    /// Frames arrive on WebRTC's render thread; the pool and the copy are touched only there.
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        display.videoGravity = .resize
        // Console pixels stay sharp blocks when scaled up to a TV.
        display.magnificationFilter = .nearest
    }

    required init?(coder: NSCoder) { nil }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pixels = pixelBuffer(frame.buffer), let sample = Self.sample(pixels) else { return }
        let display = self.display
        if display.status == .failed { display.flush() }
        display.enqueue(sample)
    }

    // MARK: - Pixel buffers

    private func pixelBuffer(_ buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let native = buffer as? RTCCVPixelBuffer, !native.requiresCropping() { return native.pixelBuffer }
        let i420 = buffer.toI420()
        let (width, height) = (Int(i420.width), Int(i420.height))
        guard let out = nv12Buffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(out, 0),
              let uv = CVPixelBufferGetBaseAddressOfPlane(out, 1) else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(out, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(out, 1)
        for row in 0..<height {
            (y + row * yStride).copyMemory(from: i420.dataY + row * Int(i420.strideY), byteCount: width)
        }
        let (cw, ch) = (Int(i420.chromaWidth), Int(i420.chromaHeight))
        for row in 0..<ch {
            let dst = (uv + row * uvStride).assumingMemoryBound(to: UInt8.self)
            let u = i420.dataU + row * Int(i420.strideU)
            let v = i420.dataV + row * Int(i420.strideV)
            for x in 0..<cw {
                dst[2 * x] = u[x]
                dst[2 * x + 1] = v[x]
            }
        }
        return out
    }

    /// An NV12 buffer of this size from a pool, remade when the size changes.
    private func nv12Buffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize != (width, height) {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            var made: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &made)
            pool = made
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        return out
    }

    /// A sample buffer shown as soon as it is enqueued.
    private static func sample(_ pixels: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
