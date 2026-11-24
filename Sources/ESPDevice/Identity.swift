// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Security state returned by GET_SECURITY_INFO (ESP32-S2 and later).
public struct SecurityInfo: Hashable, Sendable {
    /// Security flags, one bit each as the ROM reports them.
    public struct Flags: OptionSet, Hashable, Sendable {
        /// The 32 flag bits.
        public let rawValue: UInt32
        /// Flags from their raw bits.
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Secure Boot is enabled.
        public static let secureBootEnabled = Flags(rawValue: 1 << 0)
        /// Aggressive key revocation is enabled.
        public static let secureBootAggressiveRevoke = Flags(rawValue: 1 << 1)
        /// Secure Download Mode is enabled.
        public static let secureDownloadEnable = Flags(rawValue: 1 << 2)
        /// Secure Boot key 0 is revoked.
        public static let secureBootKeyRevoke0 = Flags(rawValue: 1 << 3)
        /// Secure Boot key 1 is revoked.
        public static let secureBootKeyRevoke1 = Flags(rawValue: 1 << 4)
        /// Secure Boot key 2 is revoked.
        public static let secureBootKeyRevoke2 = Flags(rawValue: 1 << 5)
        /// JTAG is disabled, and can be re-enabled through HMAC.
        public static let jtagSoftDisabled = Flags(rawValue: 1 << 6)
        /// JTAG is permanently disabled.
        public static let jtagHardDisabled = Flags(rawValue: 1 << 7)
        /// The USB peripheral is disabled.
        public static let usbDisabled = Flags(rawValue: 1 << 8)
        /// The data cache is disabled in download mode.
        public static let downloadDCacheDisabled = Flags(rawValue: 1 << 9)
        /// The instruction cache is disabled in download mode.
        public static let downloadICacheDisabled = Flags(rawValue: 1 << 10)
    }

    /// Security flags.
    public var flags: Flags
    /// Raw value of the `SPI_BOOT_CRYPT_CNT` counter (`FLASH_CRYPT_CNT` on the ESP32):
    /// encryption is enabled when an odd number of bits is set.
    public var flashCryptCount: Int
    /// One entry per purpose byte returned by the ROM.
    public var keyPurposes: [KeyPurpose]
    /// Family identifier (`ChipFamily.imageChipID`). Missing on the oldest ROMs.
    public var chipID: UInt32?
    /// Version of the ROM's security API. Missing on the oldest ROMs.
    public var apiVersion: UInt32?

    /// True if the eFuse counter has an odd number of bits set.
    public var flashEncryptionEnabled: Bool { flashCryptCount.nonzeroBitCount % 2 == 1 }

    /// Decodes the response: 4 flag bytes, 1 counter byte, 7 purpose bytes,
    /// then optionally the chip ID and API version (4 bytes each).
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

/// SPI flash identity.
public struct FlashInfo: Hashable, Sendable {
    /// JEDEC manufacturer (0xEF Winbond, 0xC8 GigaDevice, 0x20 XMC, 0x5E Zbit…).
    public var manufacturerID: UInt8
    /// Type byte (high) and capacity byte (low) of the JEDEC ID.
    public var deviceID: UInt16
    /// Size deduced from the JEDEC ID, `nil` if unknown.
    public var detectedSize: FlashSize?
    /// Flash technology.
    public var type: FlashType

    /// Raw 24-bit JEDEC ID, as returned by RDID (manufacturer in the low byte).
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
