// swift-tools-version: 6.0
// SovEmuKit: everything the app needs that is not UI or WebRTC: the input wire protocol, the
// API's models and an API client. Testable on the host with `swift test`.
import PackageDescription

let package = Package(
    name: "SovEmuKit",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [.library(name: "SovEmuKit", targets: ["SovEmuKit"])],
    dependencies: [
        // Exact, never a range: `Sources/SovEmuKit/Generated` is written by the CLI of this same
        // release (`scripts/codegen.sh` downloads it by this version), and a library ahead of its
        // generated code fails to compile.
        .package(url: "https://github.com/apollographql/apollo-ios.git", exact: "2.4.0"),
    ],
    targets: [
        .target(
            name: "SovEmuKit",
            dependencies: [
                .product(name: "Apollo", package: "apollo-ios"),
                .product(name: "ApolloAPI", package: "apollo-ios"),
            ],
            exclude: ["GraphQL"]
        ),
        .testTarget(name: "SovEmuKitTests", dependencies: ["SovEmuKit"]),
    ]
)
