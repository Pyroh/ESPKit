// SPDX-License-Identifier: MIT OR Apache-2.0

/// Famille de puce Espressif.
public enum ChipFamily: String, CaseIterable, Sendable, Hashable, Codable, CustomStringConvertible {
    case esp8266, esp32, esp32s2, esp32s3, esp32s31,
         esp32c2, esp32c3, esp32c5, esp32c6, esp32c61,
         esp32h2, esp32h21, esp32h4, esp32p4, esp32e22

    public enum Architecture: Sendable, Hashable { case xtensa, riscv }

    /// Nom commercial, par exemple « ESP32-S3 ».
    public var displayName: String {
        switch self {
        case .esp8266: "ESP8266"
        case .esp32: "ESP32"
        case .esp32s2: "ESP32-S2"
        case .esp32s3: "ESP32-S3"
        case .esp32s31: "ESP32-S31"
        case .esp32c2: "ESP32-C2"
        case .esp32c3: "ESP32-C3"
        case .esp32c5: "ESP32-C5"
        case .esp32c6: "ESP32-C6"
        case .esp32c61: "ESP32-C61"
        case .esp32h2: "ESP32-H2"
        case .esp32h21: "ESP32-H21"
        case .esp32h4: "ESP32-H4"
        case .esp32p4: "ESP32-P4"
        case .esp32e22: "ESP32-E22"
        }
    }

    public var description: String { displayName }

    public var architecture: Architecture {
        switch self {
        case .esp8266, .esp32, .esp32s2, .esp32s3: .xtensa
        default: .riscv
        }
    }

    /// Offset flash du bootloader de second niveau (0x1000, 0x0 ou 0x2000 selon la puce).
    public var bootloaderOffset: UInt32 {
        switch self {
        case .esp32, .esp32s2: 0x1000
        case .esp32c5, .esp32h4, .esp32p4, .esp32s31: 0x2000
        default: 0x0
        }
    }

    /// Identifiant écrit dans l'en-tête étendu des images (`nil` pour l'ESP8266).
    /// C'est aussi le `chip_id` que rend GET_SECURITY_INFO sur les puces récentes.
    public var imageChipID: UInt16? {
        switch self {
        case .esp8266: nil
        case .esp32: 0
        case .esp32s2: 2
        case .esp32c3: 5
        case .esp32s3: 9
        case .esp32c2: 12
        case .esp32c6: 13
        case .esp32h2: 16
        case .esp32p4: 18
        case .esp32c61: 20
        case .esp32c5: 23
        case .esp32h21: 25
        case .esp32h4: 28
        case .esp32e22: 31
        case .esp32s31: 32
        }
    }

    /// Puce dont l'`imageChipID` vaut `id`.
    public init?(imageChipID id: UInt16) {
        guard let match = ChipFamily.allCases.first(where: { $0.imageChipID == id }) else { return nil }
        self = match
    }

    /// Fréquences flash que l'en-tête d'image sait encoder pour cette puce.
    public var supportedFlashFrequencies: [FlashFrequency] {
        switch self {
        case .esp32c2: [.mhz60, .mhz30, .mhz20, .mhz15]
        case .esp32c5, .esp32c6, .esp32c61, .esp32s31: [.mhz80, .mhz40, .mhz20]
        case .esp32h2, .esp32h21, .esp32h4: [.mhz48, .mhz24, .mhz16, .mhz12]
        default: [.mhz80, .mhz40, .mhz26, .mhz20]
        }
    }

    /// Secure Boot v2 possible sur cette famille. Sur l'ESP32, seulement à partir de la révision v3.0.
    public var supportsSecureBootV2: Bool { self != .esp8266 }
}
