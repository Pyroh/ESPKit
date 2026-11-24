// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Zone mémoire d'un segment, d'après son adresse de chargement.
public enum MemoryRegion: Hashable, Sendable, CustomStringConvertible {
    /// Code mappé depuis la flash.
    case irom
    /// Données en lecture seule mappées depuis la flash.
    case drom
    /// Bus unifié (C5, C6, C61, H2, P4) : code et données partagent la même plage.
    case flash
    case iram, dram
    case rtcFast, rtcSlow
    /// RAM externe (PSRAM).
    case extram
    /// Segment de remplissage à l'adresse 0.
    case padding

    public var description: String {
        switch self {
        case .irom: "IROM"
        case .drom: "DROM"
        case .flash: "FLASH"
        case .iram: "IRAM"
        case .dram: "DRAM"
        case .rtcFast: "RTC_FAST"
        case .rtcSlow: "RTC_SLOW"
        case .extram: "EXTRAM"
        case .padding: "PADDING"
        }
    }

    /// Le segment est servi par le MMU depuis la flash : il doit être aligné sur la page.
    public var isFlashMapped: Bool { self == .irom || self == .drom || self == .flash }
}

/// Faits par puce nécessaires au format d'image : cartes mémoire, codes d'en-tête.
package struct ChipImageTraits: Sendable {
    package let chip: ChipFamily

    package init(_ chip: ChipFamily) { self.chip = chip }

    private struct Range {
        let start: UInt32
        let end: UInt32
        let region: MemoryRegion
    }

    /// Plages mémoire, de la plus spécifique à la plus générale. `nil` : puce dont ESPKit
    /// n'a pas encore la carte (H21, H4, S31, E22).
    private var ranges: [Range]? {
        switch chip {
        case .esp8266:
            [Range(start: 0x4020_0000, end: 0x4030_0000, region: .irom),
             Range(start: 0x4010_0000, end: 0x4010_8000, region: .iram),
             Range(start: 0x3FFE_8000, end: 0x4000_0000, region: .dram)]
        case .esp32:
            [Range(start: 0x3F40_0000, end: 0x3F80_0000, region: .drom),
             Range(start: 0x3F80_0000, end: 0x3FC0_0000, region: .extram),
             Range(start: 0x3FF8_0000, end: 0x3FF8_2000, region: .rtcFast),
             Range(start: 0x3FF9_0000, end: 0x4000_0000, region: .dram),
             Range(start: 0x4007_0000, end: 0x400A_0000, region: .iram),
             Range(start: 0x400A_0000, end: 0x400C_0000, region: .iram),
             Range(start: 0x400C_0000, end: 0x400C_2000, region: .rtcFast),
             Range(start: 0x400D_0000, end: 0x4040_0000, region: .irom),
             Range(start: 0x5000_0000, end: 0x5000_2000, region: .rtcSlow)]
        case .esp32s2:
            [Range(start: 0x3F00_0000, end: 0x3FF8_0000, region: .drom),
             Range(start: 0x3FF9_E000, end: 0x4000_0000, region: .dram),
             Range(start: 0x4002_0000, end: 0x4007_0000, region: .iram),
             Range(start: 0x4007_0000, end: 0x4008_0000, region: .rtcFast),
             Range(start: 0x4008_0000, end: 0x40B8_0000, region: .irom),
             Range(start: 0x5000_0000, end: 0x5000_2000, region: .rtcSlow)]
        case .esp32s3:
            [Range(start: 0x3C00_0000, end: 0x3E00_0000, region: .drom),
             Range(start: 0x3FC8_8000, end: 0x3FD0_0000, region: .dram),
             Range(start: 0x4037_0000, end: 0x403E_0000, region: .iram),
             Range(start: 0x4200_0000, end: 0x4400_0000, region: .irom),
             Range(start: 0x5000_0000, end: 0x5000_2000, region: .rtcSlow),
             Range(start: 0x600F_E000, end: 0x6010_0000, region: .rtcFast)]
        case .esp32c3:
            [Range(start: 0x3C00_0000, end: 0x3C80_0000, region: .drom),
             Range(start: 0x3FC8_0000, end: 0x3FCE_0000, region: .dram),
             Range(start: 0x4037_C000, end: 0x403E_0000, region: .iram),
             Range(start: 0x4200_0000, end: 0x4280_0000, region: .irom),
             Range(start: 0x5000_0000, end: 0x5000_2000, region: .rtcFast)]
        case .esp32c2:
            [Range(start: 0x3C00_0000, end: 0x3C40_0000, region: .drom),
             Range(start: 0x3FCA_0000, end: 0x3FCE_0000, region: .dram),
             Range(start: 0x4037_C000, end: 0x403C_0000, region: .iram),
             Range(start: 0x4200_0000, end: 0x4240_0000, region: .irom)]
        case .esp32c6, .esp32h2:
            [Range(start: 0x4200_0000, end: 0x4300_0000, region: .flash),
             Range(start: 0x4080_0000, end: 0x4088_0000, region: .iram),
             Range(start: 0x5000_0000, end: 0x5000_4000, region: .rtcFast)]
        case .esp32c5, .esp32c61:
            [Range(start: 0x4200_0000, end: 0x4400_0000, region: .flash),
             Range(start: 0x4080_0000, end: 0x4088_0000, region: .iram),
             Range(start: 0x5000_0000, end: 0x5000_4000, region: .rtcFast)]
        case .esp32p4:
            [Range(start: 0x4000_0000, end: 0x4C00_0000, region: .flash),
             Range(start: 0x4FF0_0000, end: 0x4FFC_0000, region: .iram),
             Range(start: 0x5010_8000, end: 0x5011_0000, region: .rtcFast)]
        case .esp32h21, .esp32h4, .esp32s31, .esp32e22:
            nil
        }
    }

    /// Vrai si ESPKit sait construire des images pour cette puce.
    package var hasMemoryMap: Bool { ranges != nil }

    package func region(of address: UInt32) -> MemoryRegion? {
        if address == 0 { return .padding }
        return ranges?.first { address >= $0.start && address < $0.end }?.region
    }

    package func isFlashMapped(_ address: UInt32) -> Bool {
        region(of: address)?.isFlashMapped ?? false
    }

    /// Tailles de page MMU possibles (en octets), la première étant celle par défaut.
    package var mmuPageSizes: [Int] {
        switch chip {
        case .esp32c2: [0x1_0000, 0x8000, 0x4000]
        case .esp32c6, .esp32c61, .esp32h2, .esp32h21, .esp32h4: [0x1_0000, 0x8000, 0x4000, 0x2000]
        default: [0x1_0000]
        }
    }

    // MARK: Codes d'en-tête

    package static func code(for mode: FlashMode) -> UInt8 {
        switch mode {
        case .qio: 0
        case .qout: 1
        case .dio: 2
        case .dout: 3
        }
    }

    package static func mode(forCode code: UInt8) -> FlashMode? {
        FlashMode.allCases.first { Self.code(for: $0) == code }
    }

    /// Code de taille (quartet haut de l'octet 3).
    package func code(for size: FlashSize) -> UInt8? {
        sizeTable.first { $0.size == size }?.code
    }

    package func size(forCode code: UInt8) -> FlashSize? {
        sizeTable.first { $0.code == code }?.size
    }

    private var sizeTable: [(size: FlashSize, code: UInt8)] {
        if chip == .esp8266 {
            return [(.kb512, 0x0), (.kb256, 0x1), (.mb1, 0x2), (.mb2, 0x3), (.mb4, 0x4),
                    (.mb2c1, 0x5), (.mb4c1, 0x6), (.mb8, 0x8), (.mb16, 0x9)]
        }
        return [(.mb1, 0x0), (.mb2, 0x1), (.mb4, 0x2), (.mb8, 0x3), (.mb16, 0x4),
                (.mb32, 0x5), (.mb64, 0x6), (.mb128, 0x7)]
    }

    /// Code de fréquence (quartet bas de l'octet 3). `nil` si la fréquence n'existe pas sur la
    /// puce, ou si ESPKit n'a pas encore la table de cette puce (C5, C6, C61, P4, S31, E22).
    package func code(for frequency: FlashFrequency) -> UInt8? {
        frequencyTable?[frequency]
    }

    package func frequency(forCode code: UInt8) -> FlashFrequency? {
        frequencyTable?.first { $0.value == code }?.key
    }

    private var frequencyTable: [FlashFrequency: UInt8]? {
        switch chip {
        case .esp8266, .esp32, .esp32s2, .esp32s3, .esp32c3:
            [.mhz80: 0xF, .mhz40: 0x0, .mhz26: 0x1, .mhz20: 0x2]
        case .esp32c2:
            [.mhz60: 0xF, .mhz30: 0x0, .mhz20: 0x1, .mhz15: 0x2]
        case .esp32h2, .esp32h21, .esp32h4:
            [.mhz48: 0xF, .mhz24: 0x0, .mhz16: 0x1, .mhz12: 0x2]
        default:
            nil
        }
    }

    /// Identifiant de famille UF2 (registre Microsoft `uf2families.json`).
    package var uf2FamilyID: UInt32? {
        switch chip {
        case .esp8266: 0x7EAB_61ED
        case .esp32: 0x1C5F_21B0
        case .esp32s2: 0xBFDD_4EEE
        case .esp32s3: 0xC47E_5767
        case .esp32c2: 0x2B88_D29C
        case .esp32c3: 0xD42B_A06C
        case .esp32c5: 0xF71C_0343
        case .esp32c6: 0x540D_DF62
        case .esp32c61: 0x77D8_50C4
        case .esp32h2: 0x3327_26F6
        case .esp32p4: 0x3D30_8E94
        default: nil
        }
    }
}
