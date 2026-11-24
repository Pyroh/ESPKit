// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT OR Apache-2.0

import PackageDescription

let package = Package(
    name: "ESPKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ESPKit", targets: ["ESPKit"]),
        .library(name: "ESPTargets", targets: ["ESPTargets"]),
        .library(name: "ESPTransport", targets: ["ESPTransport"]),
        .library(name: "ESPImage", targets: ["ESPImage"]),
        .library(name: "ESPSecure", targets: ["ESPSecure"]),
        .library(name: "ESPDevice", targets: ["ESPDevice"]),
        .library(name: "ESPEfuse", targets: ["ESPEfuse"]),
    ],
    dependencies: [
        // RSA, ECDSA and AES for ESPSecure (Apache-2.0).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.1.2")),
    ],
    targets: [
        // Base types, no I/O.
        .target(name: "ESPTargets"),

        // Serial ports, USB discovery, reset sequences.
        .target(name: "ESPTransport", dependencies: ["ESPTargets"]),

        // SLIP frames, ROM/stub protocol commands and responses. Pure, internal to the package.
        .target(name: "ESPProtocol"),

        // System libz.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.apt(["zlib1g-dev"])]),

        // MD5, SHA-256 and zlib: internal utilities, no external dependency.
        .target(name: "ESPSupport", dependencies: ["CZlib"]),

        // Firmware images, ELF, elf2image, merging (raw, Intel HEX, UF2). Pure, no I/O.
        .target(name: "ESPImage", dependencies: ["ESPTargets", "ESPSupport"]),

        // Secure Boot and flash encryption. Pure, no I/O.
        .target(name: "ESPSecure", dependencies: [
            "ESPTargets", "ESPSupport",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "_CryptoExtras", package: "swift-crypto"),
        ]),

        // The ESPDevice actor and its operations. Bundles the v2 stub (esp-flasher-stub).
        .target(name: "ESPDevice", dependencies: ["ESPTargets", "ESPTransport", "ESPProtocol", "ESPSupport", "ESPImage"]),

        // eFuse reading. Tables generated from ESP-IDF (Tools/efuse-codegen).
        .target(name: "ESPEfuse", dependencies: ["ESPTargets", "ESPDevice", "ESPSecure"]),

        // Umbrella: re-exports every public module.
        .target(name: "ESPKit", dependencies: ["ESPTargets", "ESPTransport", "ESPImage", "ESPSecure", "ESPDevice", "ESPEfuse"]),

        .testTarget(name: "ESPProtocolTests", dependencies: ["ESPProtocol"]),
        .testTarget(name: "ESPTargetsTests", dependencies: ["ESPTargets"]),
        .testTarget(name: "ESPSupportTests", dependencies: ["ESPSupport"]),
        .testTarget(name: "ESPTransportTests", dependencies: ["ESPTransport"]),
        .testTarget(name: "ESPImageTests", dependencies: ["ESPImage", "ESPSupport"]),
        .testTarget(name: "ESPSecureTests", dependencies: ["ESPSecure", "ESPSupport"]),
        .testTarget(name: "ESPEfuseTests", dependencies: ["ESPEfuse", "ESPSecure"]),
        .testTarget(name: "ESPDeviceTests", dependencies: ["ESPDevice", "ESPProtocol", "ESPSupport", "ESPImage", "ESPEfuse"]),

        // Tests on real boards. Skipped unless ESPKIT_PORT_ESP32 / ESPKIT_PORT_S3 are set.
        .testTarget(name: "HardwareTests", dependencies: ["ESPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
