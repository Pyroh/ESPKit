// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Généré par Tools/efuse-codegen/generate.py depuis components/efuse/esp32p4/esp_efuse_table.csv d'ESP-IDF (Apache-2.0). Ne pas modifier.

extension EfuseTable {
    static let esp32p4 = EfuseTable(chip: .esp32p4, fields: [
        EfuseDefinition(name: "WR_DIS", idfName: "WR_DIS", aliases: [], block: 0, bits: [Bits(0, 32)], description: "Disable programming of individual eFuses", category: "config", type: "uint:32", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "RD_DIS", idfName: "RD_DIS", aliases: [], block: 0, bits: [Bits(32, 7)], description: "Disable reading from BlOCK4-10", category: "config", type: "uint:7", inSummary: true, writeDisableBit: 0, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_DEVICE_EXCHG_PINS", idfName: "USB_DEVICE_EXCHG_PINS", aliases: [], block: 0, bits: [Bits(39, 1)], description: "Enable usb device exchange pins of D+ and D-", category: "usb", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_OTG11_EXCHG_PINS", idfName: "USB_OTG11_EXCHG_PINS", aliases: [], block: 0, bits: [Bits(40, 1)], description: "Enable usb otg11 exchange pins of D+ and D-", category: "usb", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_JTAG", idfName: "DIS_USB_JTAG", aliases: [], block: 0, bits: [Bits(41, 1)], description: "Represents whether the function of usb switch to jtag is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "POWERGLITCH_EN", idfName: "POWERGLITCH_EN", aliases: [], block: 0, bits: [Bits(42, 1)], description: "Represents whether power glitch function is enabled. 1: enabled. 0: disabled", category: "config", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_FORCE_DOWNLOAD", idfName: "DIS_FORCE_DOWNLOAD", aliases: [], block: 0, bits: [Bits(44, 1)], description: "Represents whether the function that forces chip into download mode is disabled or enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SPI_DOWNLOAD_MSPI_DIS", idfName: "SPI_DOWNLOAD_MSPI_DIS", aliases: [], block: 0, bits: [Bits(45, 1)], description: "Set this bit to disable accessing MSPI flash/MSPI ram by SYS AXI matrix during boot_mode_download", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_TWAI", idfName: "DIS_TWAI", aliases: [], block: 0, bits: [Bits(46, 1)], description: "Represents whether TWAI function is disabled or enabled. 1: disabled. 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "JTAG_SEL_ENABLE", idfName: "JTAG_SEL_ENABLE", aliases: [], block: 0, bits: [Bits(47, 1)], description: "Represents whether the selection between usb_to_jtag and pad_to_jtag through strapping gpio15 when both EFUSE_DIS_PAD_JTAG and EFUSE_DIS_USB_JTAG are equal to 0 is enabled or disabled. 1: enabled. 0: disabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SOFT_DIS_JTAG", idfName: "SOFT_DIS_JTAG", aliases: [], block: 0, bits: [Bits(48, 3)], description: "Represents whether JTAG is disabled in soft way. Odd number: disabled. Even number: enabled", category: "jtag", type: "uint:3", inSummary: true, writeDisableBit: 31, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_PAD_JTAG", idfName: "DIS_PAD_JTAG", aliases: [], block: 0, bits: [Bits(51, 1)], description: "Represents whether JTAG is disabled in the hard way(permanently). 1: disabled. 0: enabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MANUAL_ENCRYPT", idfName: "DIS_DOWNLOAD_MANUAL_ENCRYPT", aliases: [], block: 0, bits: [Bits(52, 1)], description: "Represents whether flash encrypt function is disabled or enabled(except in SPI boot mode). 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_PHY_SEL", idfName: "USB_PHY_SEL", aliases: [], block: 0, bits: [Bits(57, 1)], description: "TBD", category: "usb", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_HUK_GEN_STATE", idfName: "KM_HUK_GEN_STATE", aliases: [], block: 0, bits: [Bits(58, 9)], description: "Set this bit to control validation of HUK generate mode. Odd of 1 is invalid; even of 1 is valid", category: "config", type: "uint:9", inSummary: true, writeDisableBit: 19, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_RND_SWITCH_CYCLE", idfName: "KM_RND_SWITCH_CYCLE", aliases: [], block: 0, bits: [Bits(67, 2)], description: "Set bits to control key manager random number switch cycle. 0: control by register. 1: 8 km clk cycles. 2: 16 km cycles. 3: 32 km cycles", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_DEPLOY_ONLY_ONCE", idfName: "KM_DEPLOY_ONLY_ONCE", aliases: [], block: 0, bits: [Bits(69, 4)], description: "Set each bit to control whether corresponding key can only be deployed once. 1 is true; 0 is false. Bit0: ecdsa. Bit1: xts. Bit2: hmac. Bit3: ds", category: "config", type: "uint:4", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_USE_KEY_MANAGER_KEY", idfName: "FORCE_USE_KEY_MANAGER_KEY", aliases: [], block: 0, bits: [Bits(73, 4)], description: "Set each bit to control whether corresponding key must come from key manager.. 1 is true; 0 is false. Bit0: ecdsa. Bit1: xts. Bit2: hmac. Bit3: ds", category: "security", type: "uint:4", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_DISABLE_SW_INIT_KEY", idfName: "FORCE_DISABLE_SW_INIT_KEY", aliases: [], block: 0, bits: [Bits(77, 1)], description: "Set this bit to disable software written init key; and force use efuse_init_key", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "XTS_KEY_LENGTH_256", idfName: "XTS_KEY_LENGTH_256", aliases: [], block: 0, bits: [Bits(78, 1)], description: "Set this bit to configure flash encryption use xts-128 key; else use xts-256 key", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WDT_DELAY_SEL", idfName: "WDT_DELAY_SEL", aliases: [], block: 0, bits: [Bits(80, 2)], description: "Represents whether RTC watchdog timeout threshold is selected at startup. 1: selected. 0: not selected", category: "wdt", type: "uint:2", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
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
        EfuseDefinition(name: "SEC_DPA_LEVEL", idfName: "SEC_DPA_LEVEL", aliases: [], block: 0, bits: [Bits(112, 2)], description: "Represents the spa secure level by configuring the clock random divide mode", category: "security", type: "uint:2", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ECDSA_ENABLE_SOFT_K", idfName: "ECDSA_ENABLE_SOFT_K", aliases: [], block: 0, bits: [Bits(114, 1)], description: "Represents whether hardware random number k is forced used in ESDCA. 1: force used. 0: not force used", category: "security", type: "bool", inSummary: true, writeDisableBit: 17, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "CRYPT_DPA_ENABLE", idfName: "CRYPT_DPA_ENABLE", aliases: [], block: 0, bits: [Bits(115, 1)], description: "Represents whether anti-dpa attack is enabled. 1:enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_EN", idfName: "SECURE_BOOT_EN", aliases: [], block: 0, bits: [Bits(116, 1)], description: "Represents whether secure boot is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 15, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_AGGRESSIVE_REVOKE", idfName: "SECURE_BOOT_AGGRESSIVE_REVOKE", aliases: [], block: 0, bits: [Bits(117, 1)], description: "Represents whether revoking aggressive secure boot is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 16, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_TYPE", idfName: "FLASH_TYPE", aliases: [], block: 0, bits: [Bits(119, 1)], description: "The type of interfaced flash. 0: four data lines; 1: eight data lines", category: "flash", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_PAGE_SIZE", idfName: "FLASH_PAGE_SIZE", aliases: [], block: 0, bits: [Bits(120, 2)], description: "Set flash page size", category: "flash", type: "uint:2", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_ECC_EN", idfName: "FLASH_ECC_EN", aliases: [], block: 0, bits: [Bits(122, 1)], description: "Set this bit to enable ecc for flash boot", category: "flash", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_OTG_DOWNLOAD_MODE", idfName: "DIS_USB_OTG_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(123, 1)], description: "Set this bit to disable download via USB-OTG", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_TPUW", idfName: "FLASH_TPUW", aliases: [], block: 0, bits: [Bits(124, 4)], description: "Represents the flash waiting time after power-up; in unit of ms. When the value less than 15; the waiting time is the programmed value. Otherwise; the waiting time is 2 times the programmed value", category: "flash", type: "uint:4", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MODE", idfName: "DIS_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(128, 1)], description: "Represents whether Download mode is disabled or enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DIRECT_BOOT", idfName: "DIS_DIRECT_BOOT", aliases: [], block: 0, bits: [Bits(129, 1)], description: "Represents whether direct boot mode is disabled or enabled. 1: disabled. 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_ROM_PRINT", idfName: "DIS_USB_SERIAL_JTAG_ROM_PRINT", aliases: [], block: 0, bits: [Bits(130, 1)], description: "Represents whether print from USB-Serial-JTAG is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LOCK_KM_KEY", idfName: "LOCK_KM_KEY", aliases: [], block: 0, bits: [Bits(131, 1)], description: "TBD", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", idfName: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(132, 1)], description: "Represents whether the USB-Serial-JTAG download function is disabled or enabled. 1: disabled. 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ENABLE_SECURITY_DOWNLOAD", idfName: "ENABLE_SECURITY_DOWNLOAD", aliases: [], block: 0, bits: [Bits(133, 1)], description: "Represents whether security download is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "UART_PRINT_CONTROL", idfName: "UART_PRINT_CONTROL", aliases: [], block: 0, bits: [Bits(134, 2)], description: "Represents the type of UART printing. 00: force enable printing. 01: enable printing when GPIO8 is reset at low level. 10: enable printing when GPIO8 is reset at high level. 11: force disable printing", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_SEND_RESUME", idfName: "FORCE_SEND_RESUME", aliases: [], block: 0, bits: [Bits(136, 1)], description: "Represents whether ROM code is forced to send a resume command during SPI boot. 1: forced. 0:not forced", category: "flash", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_VERSION", idfName: "SECURE_VERSION", aliases: [], block: 0, bits: [Bits(137, 16)], description: "Represents the version used by ESP-IDF anti-rollback feature", category: "security", type: "uint:16", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_DISABLE_FAST_WAKE", idfName: "SECURE_BOOT_DISABLE_FAST_WAKE", aliases: [], block: 0, bits: [Bits(153, 1)], description: "Represents whether FAST VERIFY ON WAKE is disabled or enabled when Secure Boot is enabled. 1: disabled. 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "HYS_EN_PAD", idfName: "HYS_EN_PAD", aliases: [], block: 0, bits: [Bits(154, 1)], description: "Represents whether the hysteresis function of corresponding PAD is enabled. 1: enabled. 0:disabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DCDC_VSET", idfName: "DCDC_VSET", aliases: [], block: 0, bits: [Bits(155, 5)], description: "Set the dcdc voltage default", category: "config", type: "uint:5", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PXA0_TIEH_SEL_0", idfName: "PXA0_TIEH_SEL_0", aliases: [], block: 0, bits: [Bits(160, 2)], description: "TBD", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PXA0_TIEH_SEL_1", idfName: "PXA0_TIEH_SEL_1", aliases: [], block: 0, bits: [Bits(162, 2)], description: "TBD", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PXA0_TIEH_SEL_2", idfName: "PXA0_TIEH_SEL_2", aliases: [], block: 0, bits: [Bits(164, 2)], description: "TBD", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PXA0_TIEH_SEL_3", idfName: "PXA0_TIEH_SEL_3", aliases: [], block: 0, bits: [Bits(166, 2)], description: "TBD", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_DISABLE_DEPLOY_MODE", idfName: "KM_DISABLE_DEPLOY_MODE", aliases: [], block: 0, bits: [Bits(168, 4)], description: "TBD", category: "config", type: "uint:4", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "HP_PWR_SRC_SEL", idfName: "HP_PWR_SRC_SEL", aliases: [], block: 0, bits: [Bits(178, 1)], description: "HP system power source select. 0:LDO. 1: DCDC", category: "config", type: "bool", inSummary: true, writeDisableBit: 3, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DCDC_VSET_EN", idfName: "DCDC_VSET_EN", aliases: [], block: 0, bits: [Bits(179, 1)], description: "Select dcdc vset use efuse_dcdc_vset", category: "config", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_WDT", idfName: "DIS_WDT", aliases: [], block: 0, bits: [Bits(180, 1)], description: "Set this bit to disable watch dog", category: "wdt", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_SWD", idfName: "DIS_SWD", aliases: [], block: 0, bits: [Bits(181, 1)], description: "Set this bit to disable super-watchdog", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "MAC", idfName: "MAC", aliases: ["MAC_FACTORY"], block: 1, bits: [Bits(40, 8), Bits(32, 8), Bits(24, 8), Bits(16, 8), Bits(8, 8), Bits(0, 8)], description: "MAC address", category: "MAC", type: "bytes:6", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WAFER_VERSION_MINOR", idfName: "WAFER_VERSION_MINOR", aliases: [], block: 1, bits: [Bits(64, 4)], description: "Minor chip version", category: "identity", type: "uint:4", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WAFER_VERSION_MAJOR_LO", idfName: "WAFER_VERSION_MAJOR_LO", aliases: [], block: 1, bits: [Bits(68, 2)], description: "Major chip version (lower 2 bits)", category: "identity", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DISABLE_WAFER_VERSION_MAJOR", idfName: "DISABLE_WAFER_VERSION_MAJOR", aliases: [], block: 1, bits: [Bits(70, 1)], description: "Disables check of wafer version major", category: "identity", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DISABLE_BLK_VERSION_MAJOR", idfName: "DISABLE_BLK_VERSION_MAJOR", aliases: [], block: 1, bits: [Bits(71, 1)], description: "Disables check of blk version major", category: "identity", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLK_VERSION_MINOR", idfName: "BLK_VERSION_MINOR", aliases: [], block: 1, bits: [Bits(72, 3)], description: "BLK_VERSION_MINOR of BLOCK2", category: "identity", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLK_VERSION_MAJOR", idfName: "BLK_VERSION_MAJOR", aliases: [], block: 1, bits: [Bits(75, 2)], description: "BLK_VERSION_MAJOR of BLOCK2", category: "identity", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PSRAM_CAP", idfName: "PSRAM_CAP", aliases: [], block: 1, bits: [Bits(77, 3)], description: "PSRAM capacity", category: "config", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "TEMP", idfName: "TEMP", aliases: [], block: 1, bits: [Bits(80, 2)], description: "Operating temperature of the ESP chip", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PSRAM_VENDOR", idfName: "PSRAM_VENDOR", aliases: [], block: 1, bits: [Bits(82, 2)], description: "PSRAM vendor", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PKG_VERSION", idfName: "PKG_VERSION", aliases: [], block: 1, bits: [Bits(84, 3)], description: "Package version", category: "identity", type: "uint:3", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WAFER_VERSION_MAJOR_HI", idfName: "WAFER_VERSION_MAJOR_HI", aliases: [], block: 1, bits: [Bits(87, 1)], description: "Major chip version (MSB)", category: "identity", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO1_DREF", idfName: "LDO_VO1_DREF", aliases: [], block: 1, bits: [Bits(88, 4)], description: "Output VO1 parameter", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO2_DREF", idfName: "LDO_VO2_DREF", aliases: [], block: 1, bits: [Bits(92, 4)], description: "Output VO2 parameter", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO1_MUL", idfName: "LDO_VO1_MUL", aliases: [], block: 1, bits: [Bits(96, 3)], description: "Output VO1 parameter", category: "config", type: "uint:3", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO2_MUL", idfName: "LDO_VO2_MUL", aliases: [], block: 1, bits: [Bits(99, 3)], description: "Output VO2 parameter", category: "config", type: "uint:3", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO3_K", idfName: "LDO_VO3_K", aliases: [], block: 1, bits: [Bits(102, 8)], description: "Output VO3 calibration parameter", category: "config", type: "uint:8", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO3_VOS", idfName: "LDO_VO3_VOS", aliases: [], block: 1, bits: [Bits(110, 6)], description: "Output VO3 calibration parameter", category: "config", type: "uint:6", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO3_C", idfName: "LDO_VO3_C", aliases: [], block: 1, bits: [Bits(116, 6)], description: "Output VO3 calibration parameter", category: "config", type: "uint:6", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO4_K", idfName: "LDO_VO4_K", aliases: [], block: 1, bits: [Bits(122, 8)], description: "Output VO4 calibration parameter", category: "config", type: "uint:8", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO4_VOS", idfName: "LDO_VO4_VOS", aliases: [], block: 1, bits: [Bits(130, 6)], description: "Output VO4 calibration parameter", category: "config", type: "uint:6", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LDO_VO4_C", idfName: "LDO_VO4_C", aliases: [], block: 1, bits: [Bits(136, 6)], description: "Output VO4 calibration parameter", category: "config", type: "uint:6", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ACTIVE_HP_DBIAS", idfName: "ACTIVE_HP_DBIAS", aliases: [], block: 1, bits: [Bits(144, 4)], description: "Active HP DBIAS of fixed voltage", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ACTIVE_LP_DBIAS", idfName: "ACTIVE_LP_DBIAS", aliases: [], block: 1, bits: [Bits(148, 4)], description: "Active LP DBIAS of fixed voltage", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LSLP_HP_DBIAS", idfName: "LSLP_HP_DBIAS", aliases: [], block: 1, bits: [Bits(152, 4)], description: "LSLP HP DBIAS of fixed voltage", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DSLP_DBG", idfName: "DSLP_DBG", aliases: [], block: 1, bits: [Bits(156, 4)], description: "DSLP BDG of fixed voltage", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DSLP_LP_DBIAS", idfName: "DSLP_LP_DBIAS", aliases: [], block: 1, bits: [Bits(160, 5)], description: "DSLP LP DBIAS of fixed voltage", category: "config", type: "uint:5", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LP_DCDC_DBIAS_VOL_GAP", idfName: "LP_DCDC_DBIAS_VOL_GAP", aliases: [], block: 1, bits: [Bits(165, 5)], description: "DBIAS gap between LP and DCDC", category: "config", type: "uint:5", inSummary: false, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "OPTIONAL_UNIQUE_ID", idfName: "OPTIONAL_UNIQUE_ID", aliases: [], block: 2, bits: [Bits(0, 128)], description: "Optional unique 128-bit ID", category: "identity", type: "bytes:16", inSummary: true, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_AVE_INITCODE_ATTEN0", idfName: "ADC1_AVE_INITCODE_ATTEN0", aliases: [], block: 2, bits: [Bits(128, 10)], description: "Average initcode of ADC1 atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_AVE_INITCODE_ATTEN1", idfName: "ADC1_AVE_INITCODE_ATTEN1", aliases: [], block: 2, bits: [Bits(138, 10)], description: "Average initcode of ADC1 atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_AVE_INITCODE_ATTEN2", idfName: "ADC1_AVE_INITCODE_ATTEN2", aliases: [], block: 2, bits: [Bits(148, 10)], description: "Average initcode of ADC1 atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_AVE_INITCODE_ATTEN3", idfName: "ADC1_AVE_INITCODE_ATTEN3", aliases: [], block: 2, bits: [Bits(158, 10)], description: "Average initcode of ADC1 atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC2_AVE_INITCODE_ATTEN0", idfName: "ADC2_AVE_INITCODE_ATTEN0", aliases: [], block: 2, bits: [Bits(168, 10)], description: "Average initcode of ADC2 atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC2_AVE_INITCODE_ATTEN1", idfName: "ADC2_AVE_INITCODE_ATTEN1", aliases: [], block: 2, bits: [Bits(178, 10)], description: "Average initcode of ADC2 atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC2_AVE_INITCODE_ATTEN2", idfName: "ADC2_AVE_INITCODE_ATTEN2", aliases: [], block: 2, bits: [Bits(188, 10)], description: "Average initcode of ADC2 atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC2_AVE_INITCODE_ATTEN3", idfName: "ADC2_AVE_INITCODE_ATTEN3", aliases: [], block: 2, bits: [Bits(198, 10)], description: "Average initcode of ADC2 atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_HI_DOUT_ATTEN0", idfName: "ADC1_HI_DOUT_ATTEN0", aliases: [], block: 2, bits: [Bits(208, 10)], description: "HI_DOUT of ADC1 atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_HI_DOUT_ATTEN1", idfName: "ADC1_HI_DOUT_ATTEN1", aliases: [], block: 2, bits: [Bits(218, 10)], description: "HI_DOUT of ADC1 atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_HI_DOUT_ATTEN2", idfName: "ADC1_HI_DOUT_ATTEN2", aliases: [], block: 2, bits: [Bits(228, 10)], description: "HI_DOUT of ADC1 atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ADC1_HI_DOUT_ATTEN3", idfName: "ADC1_HI_DOUT_ATTEN3", aliases: [], block: 2, bits: [Bits(238, 10)], description: "HI_DOUT of ADC1 atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 21, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLOCK_USR_DATA", idfName: "USER_DATA", aliases: ["BLOCK_USR_DATA"], block: 3, bits: [Bits(0, 256)], description: "User data", category: "config", type: "bytes:32", inSummary: true, writeDisableBit: 22, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "CUSTOM_MAC", idfName: "USER_DATA.MAC_CUSTOM", aliases: ["MAC_CUSTOM", "CUSTOM_MAC"], block: 3, bits: [Bits(200, 48)], description: "Custom MAC", category: "MAC", type: "bytes:6", inSummary: true, writeDisableBit: 22, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY0", idfName: "KEY0", aliases: ["BLOCK_KEY0"], block: 4, bits: [Bits(0, 256)], description: "Key0 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 23, readDisableBit: 0, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY1", idfName: "KEY1", aliases: ["BLOCK_KEY1"], block: 5, bits: [Bits(0, 256)], description: "Key1 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 24, readDisableBit: 1, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY2", idfName: "KEY2", aliases: ["BLOCK_KEY2"], block: 6, bits: [Bits(0, 256)], description: "Key2 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 25, readDisableBit: 2, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY3", idfName: "KEY3", aliases: ["BLOCK_KEY3"], block: 7, bits: [Bits(0, 256)], description: "Key3 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 26, readDisableBit: 3, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY4", idfName: "KEY4", aliases: ["BLOCK_KEY4"], block: 8, bits: [Bits(0, 256)], description: "Key4 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 27, readDisableBit: 4, values: [:]),
        EfuseDefinition(name: "BLOCK_KEY5", idfName: "KEY5", aliases: ["BLOCK_KEY5"], block: 9, bits: [Bits(0, 256)], description: "Key5 or user data", category: "security", type: "bytes:32", inSummary: true, writeDisableBit: 28, readDisableBit: 5, values: [:]),
        EfuseDefinition(name: "ADC2_HI_DOUT_ATTEN0", idfName: "ADC2_HI_DOUT_ATTEN0", aliases: [], block: 10, bits: [Bits(0, 10)], description: "HI_DOUT of ADC2 atten0", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_HI_DOUT_ATTEN1", idfName: "ADC2_HI_DOUT_ATTEN1", aliases: [], block: 10, bits: [Bits(10, 10)], description: "HI_DOUT of ADC2 atten1", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_HI_DOUT_ATTEN2", idfName: "ADC2_HI_DOUT_ATTEN2", aliases: [], block: 10, bits: [Bits(20, 10)], description: "HI_DOUT of ADC2 atten2", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_HI_DOUT_ATTEN3", idfName: "ADC2_HI_DOUT_ATTEN3", aliases: [], block: 10, bits: [Bits(30, 10)], description: "HI_DOUT of ADC2 atten3", category: "config", type: "uint:10", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH0_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH0_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(40, 4)], description: "Gap between ADC1_ch0 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH1_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH1_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(44, 4)], description: "Gap between ADC1_ch1 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH2_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH2_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(48, 4)], description: "Gap between ADC1_ch2 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH3_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH3_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(52, 4)], description: "Gap between ADC1_ch3 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH4_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH4_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(56, 4)], description: "Gap between ADC1_ch4 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH5_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH5_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(60, 4)], description: "Gap between ADC1_ch5 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH6_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH6_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(64, 4)], description: "Gap between ADC1_ch6 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC1_CH7_ATTEN0_INITCODE_DIFF", idfName: "ADC1_CH7_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(68, 4)], description: "Gap between ADC1_ch7 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH0_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH0_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(72, 4)], description: "Gap between ADC2_ch0 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH1_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH1_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(76, 4)], description: "Gap between ADC2_ch1 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH2_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH2_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(80, 4)], description: "Gap between ADC2_ch2 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH3_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH3_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(84, 4)], description: "Gap between ADC2_ch3 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH4_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH4_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(88, 4)], description: "Gap between ADC2_ch4 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "ADC2_CH5_ATTEN0_INITCODE_DIFF", idfName: "ADC2_CH5_ATTEN0_INITCODE_DIFF", aliases: [], block: 10, bits: [Bits(92, 4)], description: "Gap between ADC2_ch5 and average initcode", category: "config", type: "uint:4", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
        EfuseDefinition(name: "TEMPERATURE_SENSOR", idfName: "TEMPERATURE_SENSOR", aliases: [], block: 10, bits: [Bits(96, 9)], description: "Temperature calibration data", category: "config", type: "uint:9", inSummary: false, writeDisableBit: 29, readDisableBit: 6, values: [:]),
    ], composites: [
        CompositeLabel(name: "WAFER_VERSION_MAJOR", block: 0, bitCount: 3, description: "calc WAFER VERSION MAJOR from (WAFER_VERSION_MAJOR_HI << 2) + WAFER_VERSION_MAJOR_LO (read only)", category: "identity", type: "uint:3"),
    ])
}

extension EfuseFieldName {
    public enum ESP32P4 {
        public static let activeHpDbias: EfuseFieldName = "ACTIVE_HP_DBIAS"
        public static let activeLpDbias: EfuseFieldName = "ACTIVE_LP_DBIAS"
        public static let adc1AveInitcodeAtten0: EfuseFieldName = "ADC1_AVE_INITCODE_ATTEN0"
        public static let adc1AveInitcodeAtten1: EfuseFieldName = "ADC1_AVE_INITCODE_ATTEN1"
        public static let adc1AveInitcodeAtten2: EfuseFieldName = "ADC1_AVE_INITCODE_ATTEN2"
        public static let adc1AveInitcodeAtten3: EfuseFieldName = "ADC1_AVE_INITCODE_ATTEN3"
        public static let adc1Ch0Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH0_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch1Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH1_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch2Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH2_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch3Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH3_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch4Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH4_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch5Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH5_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch6Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH6_ATTEN0_INITCODE_DIFF"
        public static let adc1Ch7Atten0InitcodeDiff: EfuseFieldName = "ADC1_CH7_ATTEN0_INITCODE_DIFF"
        public static let adc1HiDoutAtten0: EfuseFieldName = "ADC1_HI_DOUT_ATTEN0"
        public static let adc1HiDoutAtten1: EfuseFieldName = "ADC1_HI_DOUT_ATTEN1"
        public static let adc1HiDoutAtten2: EfuseFieldName = "ADC1_HI_DOUT_ATTEN2"
        public static let adc1HiDoutAtten3: EfuseFieldName = "ADC1_HI_DOUT_ATTEN3"
        public static let adc2AveInitcodeAtten0: EfuseFieldName = "ADC2_AVE_INITCODE_ATTEN0"
        public static let adc2AveInitcodeAtten1: EfuseFieldName = "ADC2_AVE_INITCODE_ATTEN1"
        public static let adc2AveInitcodeAtten2: EfuseFieldName = "ADC2_AVE_INITCODE_ATTEN2"
        public static let adc2AveInitcodeAtten3: EfuseFieldName = "ADC2_AVE_INITCODE_ATTEN3"
        public static let adc2Ch0Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH0_ATTEN0_INITCODE_DIFF"
        public static let adc2Ch1Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH1_ATTEN0_INITCODE_DIFF"
        public static let adc2Ch2Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH2_ATTEN0_INITCODE_DIFF"
        public static let adc2Ch3Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH3_ATTEN0_INITCODE_DIFF"
        public static let adc2Ch4Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH4_ATTEN0_INITCODE_DIFF"
        public static let adc2Ch5Atten0InitcodeDiff: EfuseFieldName = "ADC2_CH5_ATTEN0_INITCODE_DIFF"
        public static let adc2HiDoutAtten0: EfuseFieldName = "ADC2_HI_DOUT_ATTEN0"
        public static let adc2HiDoutAtten1: EfuseFieldName = "ADC2_HI_DOUT_ATTEN1"
        public static let adc2HiDoutAtten2: EfuseFieldName = "ADC2_HI_DOUT_ATTEN2"
        public static let adc2HiDoutAtten3: EfuseFieldName = "ADC2_HI_DOUT_ATTEN3"
        public static let blkVersionMajor: EfuseFieldName = "BLK_VERSION_MAJOR"
        public static let blkVersionMinor: EfuseFieldName = "BLK_VERSION_MINOR"
        public static let blockKey0: EfuseFieldName = "BLOCK_KEY0"
        public static let blockKey1: EfuseFieldName = "BLOCK_KEY1"
        public static let blockKey2: EfuseFieldName = "BLOCK_KEY2"
        public static let blockKey3: EfuseFieldName = "BLOCK_KEY3"
        public static let blockKey4: EfuseFieldName = "BLOCK_KEY4"
        public static let blockKey5: EfuseFieldName = "BLOCK_KEY5"
        public static let blockUsrData: EfuseFieldName = "BLOCK_USR_DATA"
        public static let cryptDpaEnable: EfuseFieldName = "CRYPT_DPA_ENABLE"
        public static let customMac: EfuseFieldName = "CUSTOM_MAC"
        public static let dcdcVset: EfuseFieldName = "DCDC_VSET"
        public static let dcdcVsetEn: EfuseFieldName = "DCDC_VSET_EN"
        public static let disableBlkVersionMajor: EfuseFieldName = "DISABLE_BLK_VERSION_MAJOR"
        public static let disableWaferVersionMajor: EfuseFieldName = "DISABLE_WAFER_VERSION_MAJOR"
        public static let disDirectBoot: EfuseFieldName = "DIS_DIRECT_BOOT"
        public static let disDownloadManualEncrypt: EfuseFieldName = "DIS_DOWNLOAD_MANUAL_ENCRYPT"
        public static let disDownloadMode: EfuseFieldName = "DIS_DOWNLOAD_MODE"
        public static let disForceDownload: EfuseFieldName = "DIS_FORCE_DOWNLOAD"
        public static let disPadJtag: EfuseFieldName = "DIS_PAD_JTAG"
        public static let disSwd: EfuseFieldName = "DIS_SWD"
        public static let disTwai: EfuseFieldName = "DIS_TWAI"
        public static let disUsbJtag: EfuseFieldName = "DIS_USB_JTAG"
        public static let disUsbOtgDownloadMode: EfuseFieldName = "DIS_USB_OTG_DOWNLOAD_MODE"
        public static let disUsbSerialJtagDownloadMode: EfuseFieldName = "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE"
        public static let disUsbSerialJtagRomPrint: EfuseFieldName = "DIS_USB_SERIAL_JTAG_ROM_PRINT"
        public static let disWdt: EfuseFieldName = "DIS_WDT"
        public static let dslpDbg: EfuseFieldName = "DSLP_DBG"
        public static let dslpLpDbias: EfuseFieldName = "DSLP_LP_DBIAS"
        public static let ecdsaEnableSoftK: EfuseFieldName = "ECDSA_ENABLE_SOFT_K"
        public static let enableSecurityDownload: EfuseFieldName = "ENABLE_SECURITY_DOWNLOAD"
        public static let flashEccEn: EfuseFieldName = "FLASH_ECC_EN"
        public static let flashPageSize: EfuseFieldName = "FLASH_PAGE_SIZE"
        public static let flashTpuw: EfuseFieldName = "FLASH_TPUW"
        public static let flashType: EfuseFieldName = "FLASH_TYPE"
        public static let forceDisableSwInitKey: EfuseFieldName = "FORCE_DISABLE_SW_INIT_KEY"
        public static let forceSendResume: EfuseFieldName = "FORCE_SEND_RESUME"
        public static let forceUseKeyManagerKey: EfuseFieldName = "FORCE_USE_KEY_MANAGER_KEY"
        public static let hpPwrSrcSel: EfuseFieldName = "HP_PWR_SRC_SEL"
        public static let hysEnPad: EfuseFieldName = "HYS_EN_PAD"
        public static let jtagSelEnable: EfuseFieldName = "JTAG_SEL_ENABLE"
        public static let keyPurpose0: EfuseFieldName = "KEY_PURPOSE_0"
        public static let keyPurpose1: EfuseFieldName = "KEY_PURPOSE_1"
        public static let keyPurpose2: EfuseFieldName = "KEY_PURPOSE_2"
        public static let keyPurpose3: EfuseFieldName = "KEY_PURPOSE_3"
        public static let keyPurpose4: EfuseFieldName = "KEY_PURPOSE_4"
        public static let keyPurpose5: EfuseFieldName = "KEY_PURPOSE_5"
        public static let kmDeployOnlyOnce: EfuseFieldName = "KM_DEPLOY_ONLY_ONCE"
        public static let kmDisableDeployMode: EfuseFieldName = "KM_DISABLE_DEPLOY_MODE"
        public static let kmHukGenState: EfuseFieldName = "KM_HUK_GEN_STATE"
        public static let kmRndSwitchCycle: EfuseFieldName = "KM_RND_SWITCH_CYCLE"
        public static let ldoVo1Dref: EfuseFieldName = "LDO_VO1_DREF"
        public static let ldoVo1Mul: EfuseFieldName = "LDO_VO1_MUL"
        public static let ldoVo2Dref: EfuseFieldName = "LDO_VO2_DREF"
        public static let ldoVo2Mul: EfuseFieldName = "LDO_VO2_MUL"
        public static let ldoVo3C: EfuseFieldName = "LDO_VO3_C"
        public static let ldoVo3K: EfuseFieldName = "LDO_VO3_K"
        public static let ldoVo3Vos: EfuseFieldName = "LDO_VO3_VOS"
        public static let ldoVo4C: EfuseFieldName = "LDO_VO4_C"
        public static let ldoVo4K: EfuseFieldName = "LDO_VO4_K"
        public static let ldoVo4Vos: EfuseFieldName = "LDO_VO4_VOS"
        public static let lockKmKey: EfuseFieldName = "LOCK_KM_KEY"
        public static let lpDcdcDbiasVolGap: EfuseFieldName = "LP_DCDC_DBIAS_VOL_GAP"
        public static let lslpHpDbias: EfuseFieldName = "LSLP_HP_DBIAS"
        public static let mac: EfuseFieldName = "MAC"
        public static let optionalUniqueId: EfuseFieldName = "OPTIONAL_UNIQUE_ID"
        public static let pkgVersion: EfuseFieldName = "PKG_VERSION"
        public static let powerglitchEn: EfuseFieldName = "POWERGLITCH_EN"
        public static let psramCap: EfuseFieldName = "PSRAM_CAP"
        public static let psramVendor: EfuseFieldName = "PSRAM_VENDOR"
        public static let pxa0TiehSel0: EfuseFieldName = "PXA0_TIEH_SEL_0"
        public static let pxa0TiehSel1: EfuseFieldName = "PXA0_TIEH_SEL_1"
        public static let pxa0TiehSel2: EfuseFieldName = "PXA0_TIEH_SEL_2"
        public static let pxa0TiehSel3: EfuseFieldName = "PXA0_TIEH_SEL_3"
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
        public static let temp: EfuseFieldName = "TEMP"
        public static let temperatureSensor: EfuseFieldName = "TEMPERATURE_SENSOR"
        public static let uartPrintControl: EfuseFieldName = "UART_PRINT_CONTROL"
        public static let usbDeviceExchgPins: EfuseFieldName = "USB_DEVICE_EXCHG_PINS"
        public static let usbOtg11ExchgPins: EfuseFieldName = "USB_OTG11_EXCHG_PINS"
        public static let usbPhySel: EfuseFieldName = "USB_PHY_SEL"
        public static let waferVersionMajor: EfuseFieldName = "WAFER_VERSION_MAJOR"
        public static let waferVersionMajorHi: EfuseFieldName = "WAFER_VERSION_MAJOR_HI"
        public static let waferVersionMajorLo: EfuseFieldName = "WAFER_VERSION_MAJOR_LO"
        public static let waferVersionMinor: EfuseFieldName = "WAFER_VERSION_MINOR"
        public static let wdtDelaySel: EfuseFieldName = "WDT_DELAY_SEL"
        public static let wrDis: EfuseFieldName = "WR_DIS"
        public static let xtsKeyLength256: EfuseFieldName = "XTS_KEY_LENGTH_256"
    }
}
