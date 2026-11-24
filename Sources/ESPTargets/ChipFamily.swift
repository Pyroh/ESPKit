// SPDX-License-Identifier: MIT OR Apache-2.0

/// Espressif chip family.
public enum ChipFamily: String, CaseIterable, Sendable, Hashable, Codable, CustomStringConvertible {
    /// ESP8266 (Xtensa L106). Its ROM speaks an older dialect of the protocol.
    case esp8266
    /// ESP32 (dual-core Xtensa LX6).
    case esp32
    /// ESP32-S2 (single-core Xtensa LX7, native USB).
    case esp32s2
    /// ESP32-S3 (dual-core Xtensa LX7, native USB and USB-Serial-JTAG).
    case esp32s3
    /// ESP32-S31 (RISC-V).
    case esp32s31
    /// ESP32-C2, also sold as ESP8684 (RISC-V).
    case esp32c2
    /// ESP32-C3 (RISC-V).
    case esp32c3
    /// ESP32-C5 (RISC-V, dual-band Wi-Fi).
    case esp32c5
    /// ESP32-C6 (RISC-V, Wi-Fi 6 and 802.15.4).
    case esp32c6
    /// ESP32-C61 (RISC-V).
    case esp32c61
    /// ESP32-H2 (RISC-V, 802.15.4 and Bluetooth LE).
    case esp32h2
    /// ESP32-H21 (RISC-V).
    case esp32h21
    /// ESP32-H4 (RISC-V).
    case esp32h4
    /// ESP32-P4 (dual-core RISC-V, no radio).
    case esp32p4
    /// ESP32-E22 (RISC-V). No bundled stub yet.
    case esp32e22

    /// CPU instruction set.
    public enum Architecture: Sendable, Hashable {
        /// Cadence Xtensa: the ESP8266, ESP32, ESP32-S2 and ESP32-S3.
        case xtensa
        /// RISC-V: every other chip.
        case riscv
    }

    /// Marketing name, for example "ESP32-S3".
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

    /// The marketing name (``displayName``).
    public var description: String { displayName }

    /// The chip's CPU instruction set.
    public var architecture: Architecture {
        switch self {
        case .esp8266, .esp32, .esp32s2, .esp32s3: .xtensa
        default: .riscv
        }
    }

    /// Flash offset of the second-stage bootloader (0x1000, 0x0 or 0x2000 depending on the chip).
    public var bootloaderOffset: UInt32 {
        switch self {
        case .esp32, .esp32s2: 0x1000
        case .esp32c5, .esp32h4, .esp32p4, .esp32s31: 0x2000
        default: 0x0
        }
    }

    /// Identifier written in the extended image header (`nil` for the ESP8266).
    /// It is also the `chip_id` that GET_SECURITY_INFO returns on recent chips.
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

    /// The chip whose `imageChipID` is `id`.
    public init?(imageChipID id: UInt16) {
        guard let match = ChipFamily.allCases.first(where: { $0.imageChipID == id }) else { return nil }
        self = match
    }

    /// Flash frequencies the image header can encode for this chip.
    public var supportedFlashFrequencies: [FlashFrequency] {
        switch self {
        case .esp32c2: [.mhz60, .mhz30, .mhz20, .mhz15]
        case .esp32c5, .esp32c6, .esp32c61, .esp32s31: [.mhz80, .mhz40, .mhz20]
        case .esp32h2, .esp32h21, .esp32h4: [.mhz48, .mhz24, .mhz16, .mhz12]
        default: [.mhz80, .mhz40, .mhz26, .mhz20]
        }
    }

    /// Whether this family supports Secure Boot v2. On the ESP32, only from revision v3.0.
    public var supportsSecureBootV2: Bool { self != .esp8266 }
}
