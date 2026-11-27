// swift-tools-version: 6.0
// Wraps the WebRTC xcframework that scripts/fetch-webrtc.sh downloads (LiveKit's build of
// Google's libwebrtc, pinned by SHA-256): the one with tvOS slices. LiveKit prefixes every
// Objective-C type with `LK`; the `WebRTC` module re-exports it under WebRTC's own names, so the
// apps import `WebRTC` and write `RTCPeerConnection` whichever build is underneath.
import PackageDescription

let package = Package(
    name: "WebRTC",
    platforms: [.iOS(.v18), .tvOS(.v18)],
    products: [.library(name: "WebRTC", targets: ["WebRTC"])],
    targets: [
        .binaryTarget(name: "LiveKitWebRTC", path: "LiveKitWebRTC.xcframework"),
        .target(name: "WebRTC", dependencies: ["LiveKitWebRTC"]),
    ]
)
