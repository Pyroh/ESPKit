// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Per-chip hardware facts the session needs: detection, MAC, SPI controller.
/// Values, not a class hierarchy.
struct ChipDescriptor: Sendable {
    let family: ChipFamily

    /// ROM address read for magic-value detection.
    static let magicRegister: UInt32 = 0x4000_1000

    /// Chips recognized by their magic value (those whose ROM returns no chip ID).
    static func family(forMagic magic: UInt32) -> ChipFamily? {
        switch magic {
        case 0xFFF0_C101: .esp8266
        case 0x00F0_1D83: .esp32
        case 0x0000_07C6: .esp32s2
        default: nil
        }
    }

    /// Size of the status block at the end of a response: 2 bytes for the stub and the ESP8266 ROM, 4 otherwise.
    func statusLength(stubRunning: Bool) -> Int {
        stubRunning || family == .esp8266 ? 2 : 4
    }

    // MARK: MAC

    enum MACLayout {
        /// ESP8266: OTP words MAC0, MAC1 and MAC3.
        case esp8266OTP
        /// ESP32: eFuse words 1 and 2 of block 0 (word 2 carries a CRC byte to drop).
        case esp32Efuse(base: UInt32)
        /// Other chips: two consecutive registers, big-endian 6-byte MAC.
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

    // MARK: SPI1 controller (raw flash commands)

    struct SPIRegisters: Sendable {
        let base: UInt32
        let usr: UInt32
        let usr1: UInt32
        let usr2: UInt32
        /// `nil` on the ESP8266, which stores the lengths in USR1.
        let mosiDataLength: UInt32?
        let misoDataLength: UInt32?
        let w0: UInt32
        /// The address is aligned on the most significant bits (ESP8266, ESP32).
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
        case .esp8266, .esp32: 0                         // handled above
        }
    }

    // MARK: Flash writing

    /// The ROM expects a fifth word ("encrypted write") in FLASH_BEGIN and FLASH_DEFL_BEGIN.
    /// True for every ROM except the ESP8266 and ESP32 ones; the stub does not expect it.
    var romFlashBeginHasEncryptionWord: Bool {
        family != .esp8266 && family != .esp32
    }

    // MARK: Watchdogs (USB-Serial-JTAG)

    /// RTC registers used to disable the RTC watchdog and auto-feed the super watchdog
    /// when the console is USB-Serial-JTAG. Filled in for the ESP32-S3;
    /// other chips will follow along with their tests.
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
