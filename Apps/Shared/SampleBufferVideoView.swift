// The game's picture, drawn by AVFoundation's sample-buffer layer rather than WebRTC's Metal view
// (`RTCMTLVideoView` drew nothing on an Apple TV, nor in the simulators, with LiveKit's build).
// Each decoded frame becomes a pixel buffer: a hardware decoder's own, or a software decoder's
// I420 planes copied into an NV12 one, and is shown at once (no timing of its own: the stream
// is already paced). The picture is stretched to the view, which the player shapes to the
// console's: never cropped. SovEmu.Android's `StreamView` and its `SharpDrawer`.
import Accelerate
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

    /// Frames arrive on WebRTC's render thread; the pool, the copy and the format are touched
    /// only there.
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    /// The last frame's format, kept while frames match it: made again only when the size or
    /// the decoder's pixel format changes.
    private var format: CMVideoFormatDescription?

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
        guard let frame, let pixels = pixelBuffer(frame.buffer), let sample = sample(pixels) else { return }
        let renderer = display.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
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
        if yStride == Int(i420.strideY) {
            y.copyMemory(from: i420.dataY, byteCount: yStride * height)
        } else {
            for row in 0..<height {
                (y + row * yStride).copyMemory(from: i420.dataY + row * Int(i420.strideY), byteCount: width)
            }
        }
        // U and V interleaved into NV12's CbCr plane in one vectorised pass.
        let (cw, ch) = (vImagePixelCount(i420.chromaWidth), vImagePixelCount(i420.chromaHeight))
        var u = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: i420.dataU), height: ch, width: cw,
                              rowBytes: Int(i420.strideU))
        var v = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: i420.dataV), height: ch, width: cw,
                              rowBytes: Int(i420.strideV))
        let error = withUnsafePointer(to: &u) { u in
            withUnsafePointer(to: &v) { v in
                var planes: [UnsafePointer<vImage_Buffer>?] = [u, v]
                var channels: [UnsafeMutableRawPointer?] = [uv, uv + 1]
                return vImageConvert_PlanarToChunky8(&planes, &channels, 2, 2, cw, ch, uvStride, vImage_Flags(kvImageNoFlags))
            }
        }
        return error == kvImageNoError ? out : nil
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
    private func sample(_ pixels: CVPixelBuffer) -> CMSampleBuffer? {
        if format.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: pixels) }) ?? true {
            var made: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &made)
            format = made
        }
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
