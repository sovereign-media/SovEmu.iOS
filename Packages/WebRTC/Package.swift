// swift-tools-version: 6.0
// Wraps the WebRTC xcframework that scripts/fetch-webrtc.sh downloads (pinned by SHA-256).
import PackageDescription

let package = Package(
    name: "WebRTC",
    platforms: [.iOS(.v18)],
    products: [.library(name: "WebRTC", targets: ["WebRTC"])],
    targets: [.binaryTarget(name: "WebRTC", path: "WebRTC.xcframework")]
)
