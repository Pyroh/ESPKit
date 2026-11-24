// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// État de sécurité rendu par GET_SECURITY_INFO (ESP32-S2 et suivantes).
public struct SecurityInfo: Hashable, Sendable {
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let secureBootEnabled = Flags(rawValue: 1 << 0)
        public static let secureBootAggressiveRevoke = Flags(rawValue: 1 << 1)
        public static let secureDownloadEnable = Flags(rawValue: 1 << 2)
        public static let secureBootKeyRevoke0 = Flags(rawValue: 1 << 3)
        public static let secureBootKeyRevoke1 = Flags(rawValue: 1 << 4)
        public static let secureBootKeyRevoke2 = Flags(rawValue: 1 << 5)
        public static let jtagSoftDisabled = Flags(rawValue: 1 << 6)
        public static let jtagHardDisabled = Flags(rawValue: 1 << 7)
        public static let usbDisabled = Flags(rawValue: 1 << 8)
        public static let downloadDCacheDisabled = Flags(rawValue: 1 << 9)
        public static let downloadICacheDisabled = Flags(rawValue: 1 << 10)
    }

    public var flags: Flags
    /// Valeur brute du compteur `SPI_BOOT_CRYPT_CNT` (`FLASH_CRYPT_CNT` sur ESP32) :
    /// le chiffrement est actif quand le nombre de bits à 1 est impair.
    public var flashCryptCount: Int
    /// Une entrée par octet de purpose rendu par la ROM.
    public var keyPurposes: [KeyPurpose]
    /// Identifiant de famille (`ChipFamily.imageChipID`). Absent sur les ROM les plus anciennes.
    public var chipID: UInt32?
    public var apiVersion: UInt32?

    public var flashEncryptionEnabled: Bool { flashCryptCount.nonzeroBitCount % 2 == 1 }

    /// Décode la réponse : 4 octets de flags, 1 octet de compteur, 7 octets de purposes,
    /// puis éventuellement chip ID et version d'API (4 octets chacun).
    init?(payload: Data) {
        guard payload.count >= 12 else { return nil }
        let bytes = Data(payload)
        flags = Flags(rawValue: bytes.readLE32(at: 0))
        flashCryptCount = Int(bytes[4])
        keyPurposes = bytes[5..<12].map(KeyPurpose.init(rawCode:))
        chipID = bytes.count >= 16 ? bytes.readLE32(at: 12) : nil
        apiVersion = bytes.count >= 20 ? bytes.readLE32(at: 16) : nil
    }
}

/// Identité de la flash SPI.
public struct FlashInfo: Hashable, Sendable {
    public var manufacturerID: UInt8
    /// Octet de type (poids fort) et octet de capacité (poids faible) de l'ID JEDEC.
    public var deviceID: UInt16
    /// Taille déduite de l'ID JEDEC, `nil` si inconnue.
    public var detectedSize: FlashSize?
    public var type: FlashType

    /// ID JEDEC brut sur 24 bits, tel que rendu par RDID (fabricant dans l'octet de poids faible).
    public var jedecID: UInt32 {
        UInt32(manufacturerID) | UInt32(deviceID >> 8) << 8 | UInt32(deviceID & 0xFF) << 16
    }

    init(jedecID id: UInt32, type: FlashType) {
        let manufacturer = UInt8(id & 0xFF)
        let memoryType = UInt8((id >> 8) & 0xFF)
        let capacity = UInt8((id >> 16) & 0xFF)
        self.manufacturerID = manufacturer
        self.deviceID = UInt16(memoryType) << 8 | UInt16(capacity)
        self.detectedSize = FlashSize(jedecManufacturer: manufacturer, type: memoryType, capacity: capacity)
        self.type = type
    }
}

extension Data {
    func readLE32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(self[startIndex + offset + i]) << (8 * i) }
        return value
    }
}
