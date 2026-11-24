// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// SPI access mode of the flash, as written in the image header.
public enum FlashMode: Hashable, Sendable, CaseIterable {
    case qio, qout, dio, dout
}

/// SPI flash clock frequency.
public struct FlashFrequency: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var megahertz: Int

    public init(megahertz: Int) { self.megahertz = megahertz }

    public static let mhz80 = FlashFrequency(megahertz: 80)
    public static let mhz60 = FlashFrequency(megahertz: 60)
    public static let mhz48 = FlashFrequency(megahertz: 48)
    public static let mhz40 = FlashFrequency(megahertz: 40)
    public static let mhz30 = FlashFrequency(megahertz: 30)
    public static let mhz26 = FlashFrequency(megahertz: 26)
    public static let mhz24 = FlashFrequency(megahertz: 24)
    public static let mhz20 = FlashFrequency(megahertz: 20)
    public static let mhz16 = FlashFrequency(megahertz: 16)
    public static let mhz15 = FlashFrequency(megahertz: 15)
    public static let mhz12 = FlashFrequency(megahertz: 12)

    public var description: String { "\(megahertz) MHz" }

    public static func < (lhs: FlashFrequency, rhs: FlashFrequency) -> Bool { lhs.megahertz < rhs.megahertz }
}

/// Flash size, as the image header can encode it.
public enum FlashSize: Hashable, Sendable, CaseIterable, CustomStringConvertible {
    case kb256, kb512, mb1, mb2, mb4, mb8, mb16, mb32, mb64, mb128
    /// ESP8266 variants (2 MB and 4 MB with the "c1" layout).
    case mb2c1, mb4c1

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
        default: return nil                   // 0x1C / 0x22 (256 Mo) : hors de FlashSize
        }
    }
}

/// Flash technology.
public enum FlashType: Hashable, Sendable {
    case nor, nand
}

/// Header setting: keep what the binary holds, or force a value.
public enum HeaderSetting<Value: Sendable & Hashable>: Hashable, Sendable {
    case keep
    case set(Value)
}

/// Changes applied to the bootloader header when it is written.
public struct FlashHeaderOverrides: Hashable, Sendable {
    public var mode: HeaderSetting<FlashMode> = .keep
    public var frequency: HeaderSetting<FlashFrequency> = .keep
    /// `.detect` replaces the size with the one measured on the attached flash.
    public var size: FlashSizeSetting = .keep

    public enum FlashSizeSetting: Hashable, Sendable { case keep, detect, set(FlashSize) }

    public init(mode: HeaderSetting<FlashMode> = .keep,
                frequency: HeaderSetting<FlashFrequency> = .keep,
                size: FlashSizeSetting = .keep) {
        self.mode = mode
        self.frequency = frequency
        self.size = size
    }

    public static let keep = FlashHeaderOverrides()
}

/// SPI flash wiring.
public enum SPIConnection: Hashable, Sendable {
    /// The one set by eFuses or strapping.
    case `default`
    /// ESP32 uniquement.
    case spi, hspi
    case pins(clk: UInt8, q: UInt8, d: UInt8, hd: UInt8, cs: UInt8)
}

/// Data to write at a flash address.
public struct FlashRegion: Hashable, Sendable {
    public var address: UInt32
    public var data: Data
    /// Encrypt this region while writing (flash encryption must be enabled). Phase 6.
    public var encrypt: Bool = false

    public init(address: UInt32, data: Data, encrypt: Bool = false) {
        self.address = address
        self.data = data
        self.encrypt = encrypt
    }
}
