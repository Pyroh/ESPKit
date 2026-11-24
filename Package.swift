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
        // RSA, ECDSA et AES pour ESPSecure (Apache-2.0).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "5.1.2")),
    ],
    targets: [
        // Types de base, sans I/O.
        .target(name: "ESPTargets"),

        // Ports série, découverte USB, séquences de reset.
        .target(name: "ESPTransport", dependencies: ["ESPTargets"]),

        // Trames SLIP, commandes et réponses du protocole ROM/stub. Pur, interne au package.
        .target(name: "ESPProtocol"),

        // libz du système.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.apt(["zlib1g-dev"])]),

        // MD5, SHA-256 et zlib : utilitaires internes, sans dépendance externe.
        .target(name: "ESPSupport", dependencies: ["CZlib"]),

        // Images firmware, ELF, elf2image, fusion (brut, Intel HEX, UF2). Pur, sans I/O.
        .target(name: "ESPImage", dependencies: ["ESPTargets", "ESPSupport"]),

        // Secure Boot et chiffrement flash. Pur, sans I/O.
        .target(name: "ESPSecure", dependencies: [
            "ESPTargets", "ESPSupport",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "_CryptoExtras", package: "swift-crypto"),
        ]),

        // L'acteur ESPDevice et ses opérations. Embarque le stub v2 (esp-flasher-stub).
        .target(name: "ESPDevice", dependencies: ["ESPTargets", "ESPTransport", "ESPProtocol", "ESPSupport", "ESPImage"]),

        // Lecture des eFuses. Tables générées depuis ESP-IDF (Tools/efuse-codegen).
        .target(name: "ESPEfuse", dependencies: ["ESPTargets", "ESPDevice"]),

        // Parapluie : réexporte tous les modules publics.
        .target(name: "ESPKit", dependencies: ["ESPTargets", "ESPTransport", "ESPImage", "ESPSecure", "ESPDevice", "ESPEfuse"]),

        .testTarget(name: "ESPProtocolTests", dependencies: ["ESPProtocol"]),
        .testTarget(name: "ESPTargetsTests", dependencies: ["ESPTargets"]),
        .testTarget(name: "ESPSupportTests", dependencies: ["ESPSupport"]),
        .testTarget(name: "ESPTransportTests", dependencies: ["ESPTransport"]),
        .testTarget(name: "ESPImageTests", dependencies: ["ESPImage", "ESPSupport"]),
        .testTarget(name: "ESPSecureTests", dependencies: ["ESPSecure", "ESPSupport"]),
        .testTarget(name: "ESPEfuseTests", dependencies: ["ESPEfuse"]),
        .testTarget(name: "ESPDeviceTests", dependencies: ["ESPDevice", "ESPProtocol", "ESPSupport", "ESPImage"]),

        // Tests sur carte réelle. Ignorés sauf si ESPKIT_PORT_ESP32 / ESPKIT_PORT_S3 sont définies.
        .testTarget(name: "HardwareTests", dependencies: ["ESPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
