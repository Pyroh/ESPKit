// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// SPI access mode of the flash, as written in the image header.
public enum FlashMode: Hashable, Sendable, CaseIterable {
    /// Quad I/O: address and data on four lines.
    case qio
    /// Quad output: address on one line, data on four.
    case qout
    /// Dual I/O: address and data on two lines.
    case dio
    /// Dual output: address on one line, data on two.
    case dout
}

/// SPI flash clock frequency.
public struct FlashFrequency: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Frequency in megahertz.
    public var megahertz: Int

    /// A frequency in megahertz. Whether a chip can encode it in an image header depends on the chip.
    public init(megahertz: Int) { self.megahertz = megahertz }

    /// 80 MHz.
    public static let mhz80 = FlashFrequency(megahertz: 80)
    /// 60 MHz.
    public static let mhz60 = FlashFrequency(megahertz: 60)
    /// 48 MHz.
    public static let mhz48 = FlashFrequency(megahertz: 48)
    /// 40 MHz, the default of most chips.
    public static let mhz40 = FlashFrequency(megahertz: 40)
    /// 30 MHz.
    public static let mhz30 = FlashFrequency(megahertz: 30)
    /// 26 MHz.
    public static let mhz26 = FlashFrequency(megahertz: 26)
    /// 24 MHz.
    public static let mhz24 = FlashFrequency(megahertz: 24)
    /// 20 MHz.
    public static let mhz20 = FlashFrequency(megahertz: 20)
    /// 16 MHz.
    public static let mhz16 = FlashFrequency(megahertz: 16)
    /// 15 MHz.
    public static let mhz15 = FlashFrequency(megahertz: 15)
    /// 12 MHz.
    public static let mhz12 = FlashFrequency(megahertz: 12)

    /// For example "80 MHz".
    public var description: String { "\(megahertz) MHz" }

    /// Orders frequencies from the slowest.
    public static func < (lhs: FlashFrequency, rhs: FlashFrequency) -> Bool { lhs.megahertz < rhs.megahertz }
}

/// Flash size, as the image header can encode it.
public enum FlashSize: Hashable, Sendable, CaseIterable, CustomStringConvertible {
    /// 256 KiB.
    case kb256
    /// 512 KiB.
    case kb512
    /// 1 MiB.
    case mb1
    /// 2 MiB.
    case mb2
    /// 4 MiB.
    case mb4
    /// 8 MiB.
    case mb8
    /// 16 MiB.
    case mb16
    /// 32 MiB.
    case mb32
    /// 64 MiB.
    case mb64
    /// 128 MiB.
    case mb128
    /// ESP8266 only: 2 MiB with the "c1" layout.
    case mb2c1
    /// ESP8266 only: 4 MiB with the "c1" layout.
    case mb4c1

    /// Size in bytes.
    public var byteCount: Int {
        switch self {
        case .kb256: 256 * 1024
        case .kb512: 512 * 1024
        case .mb1: 1 << 20
        case .mb2, .mb2c1: 2 << 20
        case .mb4, .mb4c1: 4 << 20
        case .mb8: 8 << 20
        case .mb16: 16 << 20
        case .mb32: 32 << 20
        case .mb64: 64 << 20
        case .mb128: 128 << 20
        }
    }

    /// The name esptool uses, for example "4MB".
    public var description: String {
        switch self {
        case .kb256: "256KB"
        case .kb512: "512KB"
        case .mb1: "1MB"
        case .mb2: "2MB"
        case .mb4: "4MB"
        case .mb8: "8MB"
        case .mb16: "16MB"
        case .mb32: "32MB"
        case .mb64: "64MB"
        case .mb128: "128MB"
        case .mb2c1: "2MB-c1"
        case .mb4c1: "4MB-c1"
        }
    }

    /// Size from the JEDEC ID returned by `RDID` (0x9F): byte 0 manufacturer, byte 1 type,
    /// byte 2 capacity. Adesto flashes (manufacturer 0x1F) encode the size in the low 5 bits
    /// of the type byte. `nil` if the code matches no known size.
    public init?(jedecManufacturer manufacturer: UInt8, type: UInt8, capacity: UInt8) {
        if manufacturer == 0x1F {
            switch type & 0x1F {
            case 0x04: self = .kb512
            case 0x05: self = .mb1
            case 0x06: self = .mb2
            case 0x07: self = .mb4
            case 0x08: self = .mb8
            case 0x09: self = .mb16
            default: return nil
            }
            return
        }
        switch capacity {
        case 0x12, 0x32: self = .kb256
        case 0x13, 0x33: self = .kb512
        case 0x14, 0x34: self = .mb1
        case 0x15, 0x35: self = .mb2
        case 0x16, 0x36: self = .mb4
        case 0x17, 0x37: self = .mb8
        case 0x18, 0x38: self = .mb16
        case 0x19, 0x39: self = .mb32
        case 0x1A, 0x20, 0x3A: self = .mb64
        case 0x1B, 0x21: self = .mb128
        default: return nil                   // 0x1C / 0x22 (256 MiB): beyond FlashSize
        }
    }
}

/// Flash technology.
public enum FlashType: Hashable, Sendable {
    /// SPI NOR flash, the usual kind.
    case nor
    /// SPI NAND flash (not supported yet).
    case nand
}

/// Header setting: keep what the binary holds, or force a value.
public enum HeaderSetting<Value: Sendable & Hashable>: Hashable, Sendable {
    /// Leave the header as it is.
    case keep
    /// Write this value.
    case set(Value)
}

/// Changes applied to the bootloader header when it is written.
public struct FlashHeaderOverrides: Hashable, Sendable {
    /// SPI mode written in the header.
    public var mode: HeaderSetting<FlashMode> = .keep
    /// Flash frequency written in the header.
    public var frequency: HeaderSetting<FlashFrequency> = .keep
    /// `.detect` replaces the size with the one measured on the attached flash.
    public var size: FlashSizeSetting = .keep

    /// Flash size written in the header.
    public enum FlashSizeSetting: Hashable, Sendable {
        /// Leave the header as it is.
        case keep
        /// Use the size detected from the flash's JEDEC ID (esptool's `detect`).
        case detect
        /// Write this size.
        case set(FlashSize)
    }

    /// Overrides for the bootloader header; every setting defaults to ``HeaderSetting/keep``.
    public init(mode: HeaderSetting<FlashMode> = .keep,
                frequency: HeaderSetting<FlashFrequency> = .keep,
                size: FlashSizeSetting = .keep) {
        self.mode = mode
        self.frequency = frequency
        self.size = size
    }

    /// No change: the header is written as the binary holds it.
    public static let keep = FlashHeaderOverrides()
}

/// SPI flash wiring.
public enum SPIConnection: Hashable, Sendable {
    /// The one set by eFuses or strapping.
    case `default`
    /// The SPI pins (ESP32 only, `--spi-connection SPI`).
    case spi
    /// The HSPI pins (ESP32 only, `--spi-connection HSPI`).
    case hspi
    /// Custom GPIOs for the clock, Q (MISO), D (MOSI), HD and CS lines.
    case pins(clk: UInt8, q: UInt8, d: UInt8, hd: UInt8, cs: UInt8)
}

/// Data to write at a flash address.
public struct FlashRegion: Hashable, Sendable {
    /// Flash offset of the first byte.
    public var address: UInt32
    /// Bytes to write.
    public var data: Data
    /// Let the chip encrypt this region with its own key while writing. Needs flash encryption
    /// enabled in the eFuses, unless `WriteFlashOptions.ignoreEncryptionEfuses`.
    public var encrypt: Bool = false

    /// A region to write at `address`, in plaintext unless `encrypt`.
    public init(address: UInt32, data: Data, encrypt: Bool = false) {
        self.address = address
        self.data = data
        self.encrypt = encrypt
    }
}
