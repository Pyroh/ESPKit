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

        // L'acteur ESPDevice et ses opérations.
        .target(name: "ESPDevice", dependencies: ["ESPTargets", "ESPTransport", "ESPProtocol"]),

        // Parapluie : réexporte tous les modules publics.
        .target(name: "ESPKit", dependencies: ["ESPTargets", "ESPTransport", "ESPDevice"]),

        .testTarget(name: "ESPProtocolTests", dependencies: ["ESPProtocol"]),
        .testTarget(name: "ESPTargetsTests", dependencies: ["ESPTargets"]),
        .testTarget(name: "ESPDeviceTests", dependencies: ["ESPDevice", "ESPProtocol"]),

        // Tests sur carte réelle. Ignorés sauf si ESPKIT_PORT_ESP32 / ESPKIT_PORT_S3 sont définies.
        .testTarget(name: "HardwareTests", dependencies: ["ESPKit"]),
    ],
    swiftLanguageModes: [.v6]
)
