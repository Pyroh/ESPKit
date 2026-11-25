// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT OR Apache-2.0

import PackageDescription

let package = Package(
    name: "ESPKit",
    platforms: [.macOS(.v15)],
    products: [
        // Everything: `import ESPKit`.
        .library(name: "ESPKit", targets: ["ESPKit"]),
        // The two pure modules, for tools that build or sign images without a chip.
        .library(name: "ESPImage", targets: ["ESPImage", "ESPTargets"]),
        .library(name: "ESPSecure", targets: ["ESPSecure", "ESPTargets"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.1.2")),
    ],
    targets: [
        .target(name: "ESPTargets"),
        .target(name: "ESPTransport", dependencies: ["ESPTargets"]),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "ESPSupport", dependencies: ["CZlib"]),
        .target(name: "ESPImage", dependencies: ["ESPTargets", "ESPSupport"]),
        .target(name: "ESPSecure", dependencies: [
            "ESPTargets", "ESPSupport",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "_CryptoExtras", package: "swift-crypto"),
        ]),
        .target(name: "ESPDevice", dependencies: ["ESPTargets", "ESPTransport", "ESPSupport", "ESPImage"]),
        .target(name: "ESPEfuse", dependencies: ["ESPTargets", "ESPDevice", "ESPSecure"]),
        .target(name: "ESPKit", dependencies: ["ESPTargets", "ESPTransport", "ESPImage", "ESPSecure", "ESPDevice", "ESPEfuse"]),

        .testTarget(name: "ESPTargetsTests", dependencies: ["ESPTargets"]),
        .testTarget(name: "ESPSupportTests", dependencies: ["ESPSupport"]),
        .testTarget(name: "ESPTransportTests", dependencies: ["ESPTransport"]),
        .testTarget(name: "ESPImageTests", dependencies: ["ESPImage", "ESPSupport"]),
        .testTarget(name: "ESPSecureTests", dependencies: ["ESPSecure", "ESPSupport"]),
        .testTarget(name: "ESPEfuseTests", dependencies: ["ESPEfuse", "ESPSecure"]),
        .testTarget(name: "ESPDeviceTests", dependencies: ["ESPDevice", "ESPSupport", "ESPImage", "ESPEfuse"]),
        // Real boards; skipped unless ESPKIT_PORT_ESP32 / ESPKIT_PORT_S3 / ESPKIT_BURN_ESP32 are set.
        .testTarget(name: "HardwareTests", dependencies: ["ESPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
