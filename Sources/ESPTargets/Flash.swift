// SPDX-License-Identifier: MIT OR Apache-2.0

/// Mode d'accès SPI de la flash, tel qu'il est écrit dans l'en-tête d'image.
public enum FlashMode: Hashable, Sendable, CaseIterable {
    case qio, qout, dio, dout
}

/// Fréquence d'horloge de la flash SPI.
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

/// Taille de flash, telle que l'en-tête d'image sait l'encoder.
public enum FlashSize: Hashable, Sendable, CaseIterable, CustomStringConvertible {
    case kb256, kb512, mb1, mb2, mb4, mb8, mb16, mb32, mb64, mb128
    /// Variantes ESP8266 (2 Mo et 4 Mo en découpage « c1 »).
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

    /// Taille d'après l'ID JEDEC rendu par `RDID` (0x9F) : octet 0 fabricant, octet 1 type,
    /// octet 2 capacité. Les flashs Adesto (fabricant 0x1F) codent la taille dans les 5 bits
    /// bas de l'octet de type. `nil` si le code ne correspond à aucune taille connue.
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

/// Technologie de la flash.
public enum FlashType: Hashable, Sendable {
    case nor, nand
}

/// Réglage d'en-tête : conserver ce qui est dans le binaire ou imposer une valeur.
public enum HeaderSetting<Value: Sendable & Hashable>: Hashable, Sendable {
    case keep
    case set(Value)
}

/// Modifications à appliquer à l'en-tête du bootloader au moment de l'écriture.
public struct FlashHeaderOverrides: Hashable, Sendable {
    public var mode: HeaderSetting<FlashMode> = .keep
    public var frequency: HeaderSetting<FlashFrequency> = .keep
    /// `.detect` remplace la taille par celle mesurée sur la flash connectée.
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

/// Câblage de la flash SPI.
public enum SPIConnection: Hashable, Sendable {
    /// Celui des eFuses ou du strapping.
    case `default`
    /// ESP32 uniquement.
    case spi, hspi
    case pins(clk: UInt8, q: UInt8, d: UInt8, hd: UInt8, cs: UInt8)
}
