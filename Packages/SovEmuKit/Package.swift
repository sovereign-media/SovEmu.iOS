// swift-tools-version: 6.0
// SovEmuKit: everything the app needs that is not UI or WebRTC: the input wire protocol, the
// API's models and an API client. Testable on the host with `swift test`.
import PackageDescription

let package = Package(
    name: "SovEmuKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "SovEmuKit", targets: ["SovEmuKit"])],
    targets: [
        .target(name: "SovEmuKit"),
        .testTarget(name: "SovEmuKitTests", dependencies: ["SovEmuKit"]),
    ]
)
