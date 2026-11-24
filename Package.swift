// swift-tools-version: 6.0
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
        .library(name: "ESPDevice", targets: ["ESPDevice"]),
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

        // L'acteur ESPDevice et ses opérations. Embarque le stub v2 (esp-flasher-stub).
        .target(name: "ESPDevice", dependencies: ["ESPTargets", "ESPTransport", "ESPProtocol", "ESPSupport"]),

        // Parapluie : réexporte tous les modules publics.
        .target(name: "ESPKit", dependencies: ["ESPTargets", "ESPTransport", "ESPDevice"]),

        .testTarget(name: "ESPProtocolTests", dependencies: ["ESPProtocol"]),
        .testTarget(name: "ESPTargetsTests", dependencies: ["ESPTargets"]),
        .testTarget(name: "ESPSupportTests", dependencies: ["ESPSupport"]),
        .testTarget(name: "ESPTransportTests", dependencies: ["ESPTransport"]),
        .testTarget(name: "ESPDeviceTests", dependencies: ["ESPDevice", "ESPProtocol", "ESPSupport"]),

        // Tests sur carte réelle. Ignorés sauf si ESPKIT_PORT_ESP32 / ESPKIT_PORT_S3 sont définies.
        .testTarget(name: "HardwareTests", dependencies: ["ESPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
