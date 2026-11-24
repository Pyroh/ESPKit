// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Généré par Tools/efuse-codegen/generate.py depuis components/efuse/esp32c6/esp_efuse_table.csv d'ESP-IDF (Apache-2.0). Ne pas modifier.

extension EfuseTable {
    static let esp32c6 = EfuseTable(chip: .esp32c6, fields: [
        EfuseDefinition(name: "WR_DIS", idfName: "WR_DIS", aliases: [], block: 0, bits: [Bits(0, 32)], description: "Disable programming of individual eFuses", category: "config", type: "uint:32", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "RD_DIS", idfName: "RD_DIS", aliases: [], block: 0, bits: [Bits(32, 7)], description: "Disable reading from BlOCK4-10", category: "config", type: "uint:7", inSummary: true, writeDisableBit: 0, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SWAP_UART_SDIO_EN", idfName: "SWAP_UART_SDIO_EN", aliases: [], block: 0, bits: [Bits(39, 1)], description: "Represents whether pad of uart and sdio is swapped or not. 1: swapped. 0: not swapped", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_ICACHE", idfName: "DIS_ICACHE", aliases: [], block: 0, bits: [Bits(40, 1)], description: "Represents whether icache is disabled or enabled. 1: disabled. 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_JTAG", idfName: "DIS_USB_JTAG", aliases: [], block: 0, bits: [Bits(41, 1)], description: "Represents whether the function of usb switch to jtag is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_ICACHE", idfName: "DIS_DOWNLOAD_ICACHE", aliases: [], block: 0, bits: [Bits(42, 1)], description: "Represents whether icache is disabled or enabled in Download mode. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG", idfName: "DIS_USB_SERIAL_JTAG", aliases: [], block: 0, bits: [Bits(43, 1)], description: "Represents whether USB-Serial-JTAG is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_FORCE_DOWNLOAD", idfName: "DIS_FORCE_DOWNLOAD", aliases: [], block: 0, bits: [Bits(44, 1)], description: "Represents whether the function that forces chip into download mode is disabled or enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SPI_DOWNLOAD_MSPI_DIS", idfName: "SPI_DOWNLOAD_MSPI_DIS", aliases: [], block: 0, bits: [Bits(45, 1)], description: "Represents whether SPI0 controller during boot_mode_download is disabled or enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 17, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_TWAI", idfName: "DIS_TWAI", aliases: ["DIS_CAN"], block: 0, bits: [Bits(46, 1)], description: "Represents whether TWAI function is disabled or enabled. 1: disabled. 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "JTAG_SEL_ENABLE", idfName: "JTAG_SEL_ENABLE", aliases: [], block: 0, bits: [Bits(47, 1)], description: "Represents whether the selection between usb_to_jtag and pad_to_jtag through strapping gpio15 when both EFUSE_DIS_PAD_JTAG and EFUSE_DIS_USB_JTAG are equal to 0 is enabled or disabled. 1: enabled. 0: disabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SOFT_DIS_JTAG", idfName: "SOFT_DIS_JTAG", aliases: [], block: 0, bits: [Bits(48, 3)], description: "Represents whether JTAG is disabled in soft way. Odd number: disabled. Even number: enabled", category: "jtag", type: "uint:3", inSummary: true, writeDisableBit: 31, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_PAD_JTAG", idfName: "DIS_PAD_JTAG", aliases: [], block: 0, bits: [Bits(51, 1)], description: "Represents whether JTAG is disabled in the hard way(permanently). 1: disabled. 0: enabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MANUAL_ENCRYPT", idfName: "DIS_DOWNLOAD_MANUAL_ENCRYPT", aliases: [], block: 0, bits: [Bits(52, 1)], description: "Represents whether flash encrypt function is disabled or enabled(except in SPI boot mode). 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_EXCHG_PINS", idfName: "USB_EXCHG_PINS", aliases: [], block: 0, bits: [Bits(57, 1)], description: "Represents whether the D+ and D- pins is exchanged. 1: exchanged. 0: not exchanged", category: "usb", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "VDD_SPI_AS_GPIO", idfName: "VDD_SPI_AS_GPIO", aliases: [], block: 0, bits: [Bits(58, 1)], description: "Represents whether vdd spi pin is functioned as gpio. 1: functioned. 0: not functioned", category: "vdd", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WDT_DELAY_SEL", idfName: "WDT_DELAY_SEL", aliases: [], block: 0, bits: [Bits(80, 2)], description: "Represents whether RTC watchdog timeout threshold is selected at startup. 1: selected. 0: not selected", category: "wdt", type: "uint:2", inSummary: true, writeDisableBit: 3, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SPI_BOOT_CRYPT_CNT", idfName: "SPI_BOOT_CRYPT_CNT", aliases: [], block: 0, bits: [Bits(82, 3)], description: "Enables flash encryption when 1 or 3 bits are set and disables otherwise", category: "security", type: "uint:3", inSummary: true, writeDisableBit: 4, readDisableBit: nil, values: [0: "Disable", 1: "Enable", 3: "Disable", 7: "Enable"]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE0", idfName: "SECURE_BOOT_KEY_REVOKE0", aliases: [], block: 0, bits: [Bits(85, 1)], description: "Revoke 1st secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 5, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE1", idfName: "SECURE_BOOT_KEY_REVOKE1", aliases: [], block: 0, bits: [Bits(86, 1)], description: "Revoke 2nd secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 6, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE2", idfName: "SECURE_BOOT_KEY_REVOKE2", aliases: [], block: 0, bits: [Bits(87, 1)], description: "Revoke 3rd secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 7, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_0", idfName: "KEY_PURPOSE_0", aliases: ["KEY0_PURPOSE"], block: 0, bits: [Bits(88, 4)], description: "Represents the purpose of Key0", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 8, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_1", idfName: "KEY_PURPOSE_1", aliases: ["KEY1_PURPOSE"], block: 0, bits: [Bits(92, 4)], description: "Represents the purpose of Key1", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 9, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_2", idfName: "KEY_PURPOSE_2", aliases: ["KEY2_PURPOSE"], block: 0, bits: [Bits(96, 4)], description: "Represents the purpose of Key2", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 10, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_3", idfName: "KEY_PURPOSE_3", aliases: ["KEY3_PURPOSE"], block: 0, bits: [Bits(100, 4)], description: "Represents the purpose of Key3", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 11, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_4", idfName: "KEY_PURPOSE_4", aliases: ["KEY4_PURPOSE"], block: 0, bits: [Bits(104, 4)], description: "Represents the purpose of Key4", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 12, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_5", idfName: "KEY_PURPOSE_5", aliases: ["KEY5_PURPOSE"], block: 0, bits: [Bits(108, 4)], description: "Represents the purpose of Key5", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 13, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SEC_DPA_LEVEL", idfName: "SEC_DPA_LEVEL", aliases: ["DPA_SEC_LEVEL"], block: 0, bits: [Bits(112, 2)], description: "Represents the spa secure level by configuring the clock random divide mode", category: "security", type: "uint:2", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "CRYPT_DPA_ENABLE", idfName: "CRYPT_DPA_ENABLE", aliases: [], block: 0, bits: [Bits(114, 1)], description: "Represents whether anti-dpa attack is enabled. 1:enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_EN", idfName: "SECURE_BOOT_EN", aliases: [], block: 0, bits: [Bits(116, 1)], description: "Represents whether secure boot is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 15, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_AGGRESSIVE_REVOKE", idfName: "SECURE_BOOT_AGGRESSIVE_REVOKE", aliases: [], block: 0, bits: [Bits(117, 1)], description: "Represents whether revoking aggressive secure boot is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 16, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_TPUW", idfName: "FLASH_TPUW", aliases: [], block: 0, bits: [Bits(124, 4)], description: "Represents the flash waiting time after power-up; in unit of ms. When the value less than 15; the waiting time is the programmed value. Otherwise; the waiting time is 2 times the programmed value", category: "flash", type: "uint:4", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MODE", idfName: "DIS_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(128, 1)], description: "Represents whether Download mode is disabled or enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DIRECT_BOOT", idfName: "DIS_DIRECT_BOOT", aliases: [], block: 0, bits: [Bits(129, 1)], description: "Represents whether direct boot mode is disabled or enabled. 1: disabled. 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_ROM_PRINT", idfName: "DIS_USB_SERIAL_JTAG_ROM_PRINT", aliases: ["DIS_USB_PRINT"], block: 0, bits: [Bits(130, 1)], description: "Represents whether print from USB-Serial-JTAG is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", idfName: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(132, 1)], description: "Represents whether the USB-Serial-JTAG download function is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ENABLE_SECURITY_DOWNLOAD", idfName: "ENABLE_SECURITY_DOWNLOAD", aliases: [], block: 0, bits: [Bits(133, 1)], description: "Represents whether security download is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "UART_PRINT_CONTROL", idfName: "UART_PRINT_CONTROL", aliases: [], block: 0, bits: [Bits(134, 2)], description: "Set the default UARTboot message output mode", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [0: "Enable", 1: "Enable when GPIO8 is low at reset", 2: "Enable when GPIO8 is high at reset", 3: "Disable"]),
        EfuseDefinition(name: "FORCE_SEND_RESUME", idfName: "FORCE_SEND_RESUME", aliases: [], block: 0, bits: [Bits(141, 1)], description: "Represents whether ROM code is forced to send a resume command during SPI boot. 1: forced. 0:not forced", category: "flash", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_VERSION", idfName: "SECURE_VERSION", aliases: [], block: 0, bits: [Bits(142, 16)], description: "Represents the version used by ESP-IDF anti-rollback feature", category: "security", type: "uint:16", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_DISABLE_FAST_WAKE", idfName: "SECURE_BOOT_DISABLE_FAST_WAKE", aliases: [], block: 0, bits: [Bits(158, 1)], description: "Represents whether FAST VERIFY ON WAKE is disabled or enabled when Secure Boot is enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 19, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DISABLE_WAFER_VERSION_MAJOR", idfName: "DISABLE_WAFER_VERSION_MAJOR", aliases: [], block: 0, bits: [Bits(160, 1)], description: "Disables check of wafer version major", category: "identity", type: "bool", inSummary: true, writeDisableBit: 19, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DISABLE_BLK_VERSION_MAJOR", idfName: "DISABLE_BLK_VERSION_MAJOR", aliases: [], block: 0, bits: [Bits(161, 1)], description: "Disables check of blk version major", category: "identity", type: "bool", inSummary: true, writeDisableBit: 19, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "MAC", idfName: "MAC", aliases: ["MAC_FACTORY"], block: 1, bits: [Bits(40, 8), Bits(32, 8), Bits(24, 8), Bits(16, 8), Bits(8, 8), Bits(0, 8)], description: "MAC address", category: "MAC", type: "bytes:6", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "MAC_EXT", idfName: "MAC_EXT", aliases: [], block: 1, bits: [Bits(56, 8), Bits(48, 8)], description: "Stores the extended bits of MAC address", category: "MAC", type: "bytes:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ACTIVE_HP_DBIAS", idfName: "ACTIVE_HP_DBIAS", aliases: [], block: 1, bits: [Bits(64, 5)], description: "Stores the active hp dbias", category: "config", type: "uint:5", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ACTIVE_LP_DBIAS", idfName: "ACTIVE_LP_DBIAS", aliases: [], block: 1, bits: [Bits(69, 5)], description: "Stores the active lp dbias", category: "config", type: "uint:5", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LSLP_HP_DBG", idfName: "LSLP_HP_DBG", aliases: [], block: 1, bits: [Bits(74, 2)], description: "Stores the lslp hp dbg", category: "config", type: "uint:2", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LSLP_HP_DBIAS", idfName: "LSLP_HP_DBIAS", aliases: [], block: 1, bits: [Bits(76, 4)], description: "Stores the lslp hp dbias", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DSLP_LP_DBG", idfName: "DSLP_LP_DBG", aliases: [], block: 1, bits: [Bits(80, 3)], description: "Stores the dslp lp dbg", category: "config", type: "uint:3", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DSLP_LP_DBIAS", idfName: "DSLP_LP_DBIAS", aliases: [], block: 1, bits: [Bits(83, 4)], description: "Stores the dslp lp dbias", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DBIAS_VOL_GAP", idfName: "DBIAS_VOL_GAP", aliases: [], block: 1, bits: [Bits(87, 5)], description: "Stores the hp and lp dbias vol gap", category: "config", type: "uint:5", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WAFER_VERSION_MINOR", idfName: "WAFER_VERSION_MINOR", aliases: [], block: 1, bits: [Bits(114, 4)], description: "", category: "identity", type: "uint:4", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WAFER_VERSION_MAJOR", idfName: "WAFER_VERSION_MAJOR", aliases: [], block: 1, bits: [Bits(118, 2)], description: "", category: "identity", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PKG_VERSION", idfName: "PKG_VERSION", aliases: [], block: 1, bits: [Bits(120, 3)], description: "Package version", category: "identity", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLK_VERSION_MINOR", idfName: "BLK_VERSION_MINOR", aliases: [], block: 1, bits: [Bits(123, 3)], description: "BLK_VERSION_MINOR of BLOCK2", category: "identity", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLK_VERSION_MAJOR", idfName: "BLK_VERSION_MAJOR", aliases: [], block: 1, bits: [Bits(126, 2)], description: "BLK_VERSION_MAJOR of BLOCK2", category: "identity", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_CAP", idfName: "FLASH_CAP", aliases: [], block: 1, bits: [Bits(128, 3)], description: "", category: "flash", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_TEMP", idfName: "FLASH_TEMP", aliases: [], block: 1, bits: [Bits(131, 2)], description: "", category: "flash", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_VENDOR", idfName: "FLASH_VENDOR", aliases: [], block: 1, bits: [Bits(133, 3)], description: "", category: "flash", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "OPTIONAL_UNIQUE_ID", idfName: "OPTIONAL_UNIQUE_ID", aliases: [], block: 2, bits: [Bits(0, 128)], description: "Optional unique 128-bit ID", category: "identity", type: "bytes:16", inSummary: true, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "TEMP_CALIB", idfName: "TEMP_CALIB", aliases: [], block: 2, bits: [Bits(128, 9)], description: "Temperature calibration data", category: "config", type: "uint:9", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "OCODE", idfName: "OCODE", aliases: [], block: 2, bits: [Bits(137, 8)], description: "ADC OCode", category: "config", type: "uint:8", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0", idfName: "ADC1_INIT_CODE_ATTEN0", aliases: [], block: 2, bits: [Bits(145, 10)], description: "ADC1 init code at atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN1", idfName: "ADC1_INIT_CODE_ATTEN1", aliases: [], block: 2, bits: [Bits(155, 10)], description: "ADC1 init code at atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN2", idfName: "ADC1_INIT_CODE_ATTEN2", aliases: [], block: 2, bits: [Bits(165, 10)], description: "ADC1 init code at atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN3", idfName: "ADC1_INIT_CODE_ATTEN3", aliases: [], block: 2, bits: [Bits(175, 10)], description: "ADC1 init code at atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_CAL_VOL_ATTEN0", idfName: "ADC1_CAL_VOL_ATTEN0", aliases: [], block: 2, bits: [Bits(185, 10)], description: "ADC1 calibration voltage at atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_CAL_VOL_ATTEN1", idfName: "ADC1_CAL_VOL_ATTEN1", aliases: [], block: 2, bits: [Bits(195, 10)], description: "ADC1 calibration voltage at atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_CAL_VOL_ATTEN2", idfName: "ADC1_CAL_VOL_ATTEN2", aliases: [], block: 2, bits: [Bits(205, 10)], description: "ADC1 calibration voltage at atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_CAL_VOL_ATTEN3", idfName: "ADC1_CAL_VOL_ATTEN3", aliases: [], block: 2, bits: [Bits(215, 10)], description: "ADC1 calibration voltage at atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH0", idfName: "ADC1_INIT_CODE_ATTEN0_CH0", aliases: [], block: 2, bits: [Bits(225, 4)], description: "ADC1 init code at atten0 ch0", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH1", idfName: "ADC1_INIT_CODE_ATTEN0_CH1", aliases: [], block: 2, bits: [Bits(229, 4)], description: "ADC1 init code at atten0 ch1", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH2", idfName: "ADC1_INIT_CODE_ATTEN0_CH2", aliases: [], block: 2, bits: [Bits(233, 4)], description: "ADC1 init code at atten0 ch2", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH3", idfName: "ADC1_INIT_CODE_ATTEN0_CH3", aliases: [], block: 2, bits: [Bits(237, 4)], description: "ADC1 init code at atten0 ch3", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH4", idfName: "ADC1_INIT_CODE_ATTEN0_CH4", aliases: [], block: 2, bits: [Bits(241, 4)], description: "ADC1 init code at atten0 ch4", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH5", idfName: "ADC1_INIT_CODE_ATTEN0_CH5", aliases: [], block: 2, bits: [Bits(245, 4)], description: "ADC1 init code at atten0 ch5", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_INIT_CODE_ATTEN0_CH6", idfName: "ADC1_INIT_CODE_ATTEN0_CH6", aliases: [], block: 2, bits: [Bits(249, 4)], description: "ADC1 init code at atten0 ch6", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLOCK_USR_DATA", idfName: "USER_DATA", aliases: ["BLOCK_USR_DATA"], block: 3, bits: [Bits(0, 256)], description: "User data", category: "config", type: "bytes:32", inSummary: true, writeDisableBit: 22, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "CUSTOM_MAC", idfName: "USER_DATA.MAC_CUSTOM", aliases: ["MAC_CUSTOM", "CUSTOM_MAC"], block: 3, bits: [Bits(200, 48)], description: "Custom MAC", category: "MAC", type: "bytes:6", inSummary: true, writeDisableBit: 22, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY0", idfName: "KEY0", aliases: ["BLOCK_KEY0"], block: 4, bits: [Bits(0, 256)], description: "Key0 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 23, readDisableBit: 0, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY1", idfName: "KEY1", aliases: ["BLOCK_KEY1"], block: 5, bits: [Bits(0, 256)], description: "Key1 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 24, readDisableBit: 1, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY2", idfName: "KEY2", aliases: ["BLOCK_KEY2"], block: 6, bits: [Bits(0, 256)], description: "Key2 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 25, readDisableBit: 2, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY3", idfName: "KEY3", aliases: ["BLOCK_KEY3"], block: 7, bits: [Bits(0, 256)], description: "Key3 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 26, readDisableBit: 3, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY4", idfName: "KEY4", aliases: ["BLOCK_KEY4"], block: 8, bits: [Bits(0, 256)], description: "Key4 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 27, readDisableBit: 4, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY5", idfName: "KEY5", aliases: ["BLOCK_KEY5"], block: 9, bits: [Bits(0, 256)], description: "Key5 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 28, readDisableBit: 5, values: [:]),
        EfuseDefinition(name: "BLOCK_SYS_DATA2", idfName: "SYS_DATA_PART2", aliases: ["BLOCK_SYS_DATA2"], block: 10, bits: [Bits(0, 256)], description: "System data part 2 (reserved)", category: "config", type: "bytes:32", inSummary: true, writeDisableBit: 29, readDisableBit: 6, values: [:]),
    ], composites: [
        CompositeLabel(name: "MAC_EUI64", block: 1, bitCount: 64, description: "calc MAC_EUI64 = MAC[0]:MAC[1]:MAC[2]:MAC_EXT[0]:MAC_EXT[1]:MAC[3]:MAC[4]:MAC[5]", category: "MAC", type: "bytes:8"),
    ])
}

extension EfuseFieldName {
    public enum ESP32C6 {
        public static let activeHpDbias: EfuseFieldName = "ACTIVE_HP_DBIAS"
        public static let activeLpDbias: EfuseFieldName = "ACTIVE_LP_DBIAS"
        public static let adc1CalVolAtten0: EfuseFieldName = "ADC1_CAL_VOL_ATTEN0"
        public static let adc1CalVolAtten1: EfuseFieldName = "ADC1_CAL_VOL_ATTEN1"
        public static let adc1CalVolAtten2: EfuseFieldName = "ADC1_CAL_VOL_ATTEN2"
        public static let adc1CalVolAtten3: EfuseFieldName = "ADC1_CAL_VOL_ATTEN3"
        public static let adc1InitCodeAtten0: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0"
        public static let adc1InitCodeAtten0Ch0: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH0"
        public static let adc1InitCodeAtten0Ch1: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH1"
        public static let adc1InitCodeAtten0Ch2: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH2"
        public static let adc1InitCodeAtten0Ch3: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH3"
        public static let adc1InitCodeAtten0Ch4: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH4"
        public static let adc1InitCodeAtten0Ch5: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH5"
        public static let adc1InitCodeAtten0Ch6: EfuseFieldName = "ADC1_INIT_CODE_ATTEN0_CH6"
        public static let adc1InitCodeAtten1: EfuseFieldName = "ADC1_INIT_CODE_ATTEN1"
        public static let adc1InitCodeAtten2: EfuseFieldName = "ADC1_INIT_CODE_ATTEN2"
        public static let adc1InitCodeAtten3: EfuseFieldName = "ADC1_INIT_CODE_ATTEN3"
        public static let blkVersionMajor: EfuseFieldName = "BLK_VERSION_MAJOR"
        public static let blkVersionMinor: EfuseFieldName = "BLK_VERSION_MINOR"
        public static let blockKey0: EfuseFieldName = "BLOCK_KEY0"
        public static let blockKey1: EfuseFieldName = "BLOCK_KEY1"
        public static let blockKey2: EfuseFieldName = "BLOCK_KEY2"
        public static let blockKey3: EfuseFieldName = "BLOCK_KEY3"
        public static let blockKey4: EfuseFieldName = "BLOCK_KEY4"
        public static let blockKey5: EfuseFieldName = "BLOCK_KEY5"
        public static let blockSysData2: EfuseFieldName = "BLOCK_SYS_DATA2"
        public static let blockUsrData: EfuseFieldName = "BLOCK_USR_DATA"
        public static let cryptDpaEnable: EfuseFieldName = "CRYPT_DPA_ENABLE"
        public static let customMac: EfuseFieldName = "CUSTOM_MAC"
        public static let dbiasVolGap: EfuseFieldName = "DBIAS_VOL_GAP"
        public static let disableBlkVersionMajor: EfuseFieldName = "DISABLE_BLK_VERSION_MAJOR"
        public static let disableWaferVersionMajor: EfuseFieldName = "DISABLE_WAFER_VERSION_MAJOR"
        public static let disDirectBoot: EfuseFieldName = "DIS_DIRECT_BOOT"
        public static let disDownloadIcache: EfuseFieldName = "DIS_DOWNLOAD_ICACHE"
        public static let disDownloadManualEncrypt: EfuseFieldName = "DIS_DOWNLOAD_MANUAL_ENCRYPT"
        public static let disDownloadMode: EfuseFieldName = "DIS_DOWNLOAD_MODE"
        public static let disForceDownload: EfuseFieldName = "DIS_FORCE_DOWNLOAD"
        public static let disIcache: EfuseFieldName = "DIS_ICACHE"
        public static let disPadJtag: EfuseFieldName = "DIS_PAD_JTAG"
        public static let disTwai: EfuseFieldName = "DIS_TWAI"
        public static let disUsbJtag: EfuseFieldName = "DIS_USB_JTAG"
        public static let disUsbSerialJtag: EfuseFieldName = "DIS_USB_SERIAL_JTAG"
        public static let disUsbSerialJtagDownloadMode: EfuseFieldName = "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE"
        public static let disUsbSerialJtagRomPrint: EfuseFieldName = "DIS_USB_SERIAL_JTAG_ROM_PRINT"
        public static let dslpLpDbg: EfuseFieldName = "DSLP_LP_DBG"
        public static let dslpLpDbias: EfuseFieldName = "DSLP_LP_DBIAS"
        public static let enableSecurityDownload: EfuseFieldName = "ENABLE_SECURITY_DOWNLOAD"
        public static let flashCap: EfuseFieldName = "FLASH_CAP"
        public static let flashTemp: EfuseFieldName = "FLASH_TEMP"
        public static let flashTpuw: EfuseFieldName = "FLASH_TPUW"
        public static let flashVendor: EfuseFieldName = "FLASH_VENDOR"
        public static let forceSendResume: EfuseFieldName = "FORCE_SEND_RESUME"
        public static let jtagSelEnable: EfuseFieldName = "JTAG_SEL_ENABLE"
        public static let keyPurpose0: EfuseFieldName = "KEY_PURPOSE_0"
        public static let keyPurpose1: EfuseFieldName = "KEY_PURPOSE_1"
        public static let keyPurpose2: EfuseFieldName = "KEY_PURPOSE_2"
        public static let keyPurpose3: EfuseFieldName = "KEY_PURPOSE_3"
        public static let keyPurpose4: EfuseFieldName = "KEY_PURPOSE_4"
        public static let keyPurpose5: EfuseFieldName = "KEY_PURPOSE_5"
        public static let lslpHpDbg: EfuseFieldName = "LSLP_HP_DBG"
        public static let lslpHpDbias: EfuseFieldName = "LSLP_HP_DBIAS"
        public static let mac: EfuseFieldName = "MAC"
        public static let macEui64: EfuseFieldName = "MAC_EUI64"
        public static let macExt: EfuseFieldName = "MAC_EXT"
        public static let ocode: EfuseFieldName = "OCODE"
        public static let optionalUniqueId: EfuseFieldName = "OPTIONAL_UNIQUE_ID"
        public static let pkgVersion: EfuseFieldName = "PKG_VERSION"
        public static let rdDis: EfuseFieldName = "RD_DIS"
        public static let secureBootAggressiveRevoke: EfuseFieldName = "SECURE_BOOT_AGGRESSIVE_REVOKE"
        public static let secureBootDisableFastWake: EfuseFieldName = "SECURE_BOOT_DISABLE_FAST_WAKE"
        public static let secureBootEn: EfuseFieldName = "SECURE_BOOT_EN"
        public static let secureBootKeyRevoke0: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE0"
        public static let secureBootKeyRevoke1: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE1"
        public static let secureBootKeyRevoke2: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE2"
        public static let secureVersion: EfuseFieldName = "SECURE_VERSION"
        public static let secDpaLevel: EfuseFieldName = "SEC_DPA_LEVEL"
        public static let softDisJtag: EfuseFieldName = "SOFT_DIS_JTAG"
        public static let spiBootCryptCnt: EfuseFieldName = "SPI_BOOT_CRYPT_CNT"
        public static let spiDownloadMspiDis: EfuseFieldName = "SPI_DOWNLOAD_MSPI_DIS"
        public static let swapUartSdioEn: EfuseFieldName = "SWAP_UART_SDIO_EN"
        public static let tempCalib: EfuseFieldName = "TEMP_CALIB"
        public static let uartPrintControl: EfuseFieldName = "UART_PRINT_CONTROL"
        public static let usbExchgPins: EfuseFieldName = "USB_EXCHG_PINS"
        public static let vddSpiAsGpio: EfuseFieldName = "VDD_SPI_AS_GPIO"
        public static let waferVersionMajor: EfuseFieldName = "WAFER_VERSION_MAJOR"
        public static let waferVersionMinor: EfuseFieldName = "WAFER_VERSION_MINOR"
        public static let wdtDelaySel: EfuseFieldName = "WDT_DELAY_SEL"
        public static let wrDis: EfuseFieldName = "WR_DIS"
    }
}
