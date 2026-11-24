// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Faits matériels par puce dont la session a besoin : détection, MAC, contrôleur SPI.
/// Des valeurs, pas une hiérarchie de classes.
struct ChipDescriptor: Sendable {
    let family: ChipFamily

    /// Adresse ROM lue pour la détection par valeur magique.
    static let magicRegister: UInt32 = 0x4000_1000

    /// Puces reconnues par la valeur magique (celles dont la ROM ne rend pas de chip ID).
    static func family(forMagic magic: UInt32) -> ChipFamily? {
        switch magic {
        case 0xFFF0_C101: .esp8266
        case 0x00F0_1D83: .esp32
        case 0x0000_07C6: .esp32s2
        default: nil
        }
    }

    /// Taille du bloc d'état en fin de réponse : 2 octets pour le stub et la ROM ESP8266, 4 sinon.
    func statusLength(stubRunning: Bool) -> Int {
        stubRunning || family == .esp8266 ? 2 : 4
    }

    // MARK: MAC

    enum MACLayout {
        /// ESP8266 : mots OTP MAC0, MAC1 et MAC3.
        case esp8266OTP
        /// ESP32 : mots eFuse 1 et 2 du bloc 0 (le mot 2 porte un octet de CRC à retirer).
        case esp32Efuse(base: UInt32)
        /// Autres puces : deux registres consécutifs, MAC en big-endian sur 6 octets.
        case register(UInt32)
    }

    var macLayout: MACLayout {
        switch family {
        case .esp8266: .esp8266OTP
        case .esp32: .esp32Efuse(base: 0x3FF5_A000)
        case .esp32s2: .register(0x3F41_A044)
        case .esp32s3: .register(0x6000_7044)
        case .esp32c2: .register(0x6000_8840)
        case .esp32c3: .register(0x6000_8844)
        case .esp32c5, .esp32c61: .register(0x600B_4844)
        case .esp32c6, .esp32h2: .register(0x600B_0844)
        case .esp32h21: .register(0x600B_4044)
        case .esp32h4: .register(0x600B_1844)
        case .esp32p4: .register(0x5012_D044)
        case .esp32e22: .register(0xC400_8044)
        case .esp32s31: .register(0x2071_5050)
        }
    }

    static let esp8266OTPMAC0: UInt32 = 0x3FF0_0050
    static let esp8266OTPMAC1: UInt32 = 0x3FF0_0054
    static let esp8266OTPMAC3: UInt32 = 0x3FF0_005C

    // MARK: Contrôleur SPI1 (commandes flash brutes)

    struct SPIRegisters: Sendable {
        let base: UInt32
        let usr: UInt32
        let usr1: UInt32
        let usr2: UInt32
        /// `nil` sur l'ESP8266, qui range les longueurs dans USR1.
        let mosiDataLength: UInt32?
        let misoDataLength: UInt32?
        let w0: UInt32
        /// L'adresse est alignée sur les bits de poids fort (ESP8266, ESP32).
        let addressInMSB: Bool

        var cmd: UInt32 { base }
        var addr: UInt32 { base + 0x04 }
    }

    var spi: SPIRegisters {
        switch family {
        case .esp8266:
            SPIRegisters(base: 0x6000_0200, usr: 0x1C, usr1: 0x20, usr2: 0x24,
                         mosiDataLength: nil, misoDataLength: nil, w0: 0x40, addressInMSB: true)
        case .esp32:
            SPIRegisters(base: 0x3FF4_2000, usr: 0x1C, usr1: 0x20, usr2: 0x24,
                         mosiDataLength: 0x28, misoDataLength: 0x2C, w0: 0x80, addressInMSB: true)
        default:
            SPIRegisters(base: spiBaseForRecentChips, usr: 0x18, usr1: 0x1C, usr2: 0x20,
                         mosiDataLength: 0x24, misoDataLength: 0x28, w0: 0x58, addressInMSB: false)
        }
    }

    private var spiBaseForRecentChips: UInt32 {
        switch family {
        case .esp32s2: 0x3F40_2000
        case .esp32s3, .esp32c2, .esp32c3: 0x6000_2000
        case .esp32c5, .esp32c6, .esp32c61, .esp32h2, .esp32h21: 0x6000_3000
        case .esp32h4: 0x6009_9000
        case .esp32p4: 0x5008_D000
        case .esp32s31: 0x2050_1000
        case .esp32e22: 0xC300_3000
        case .esp8266, .esp32: 0                         // traités plus haut
        }
    }

    // MARK: Écriture flash

    /// La ROM attend un cinquième mot (« écriture chiffrée ») dans FLASH_BEGIN et FLASH_DEFL_BEGIN.
    /// Vrai pour toutes les ROM sauf celles de l'ESP8266 et de l'ESP32 ; le stub ne l'attend pas.
    var romFlashBeginHasEncryptionWord: Bool {
        family != .esp8266 && family != .esp32
    }

    // MARK: Watchdogs (USB-Serial-JTAG)

    /// Registres RTC utilisés pour neutraliser le watchdog RTC et nourrir automatiquement le
    /// super-watchdog quand la console est l'USB-Serial-JTAG. Renseigné pour l'ESP32-S3 ;
    /// les autres puces suivront avec leurs tests.
    struct RTCWatchdog: Sendable {
        let wdtConfig0: UInt32
        let wdtConfig1: UInt32
        let wdtWriteProtect: UInt32
        let wdtKey: UInt32
        let swdConfig: UInt32
        let swdWriteProtect: UInt32
        let swdKey: UInt32
        let swdAutoFeed: UInt32
    }

    var rtcWatchdog: RTCWatchdog? {
        switch family {
        case .esp32s3:
            RTCWatchdog(wdtConfig0: 0x6000_8098, wdtConfig1: 0x6000_809C, wdtWriteProtect: 0x6000_80B0,
                        wdtKey: 0x50D8_3AA1, swdConfig: 0x6000_80B4, swdWriteProtect: 0x6000_80B8,
                        swdKey: 0x8F1D_312A, swdAutoFeed: 1 << 31)
        default:
            nil
        }
    }
}
