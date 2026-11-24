// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Généré par Tools/efuse-codegen/generate.py depuis components/efuse/esp32h4/esp_efuse_table.csv d'ESP-IDF (Apache-2.0). Ne pas modifier.

extension EfuseTable {
    static let esp32h4 = EfuseTable(chip: .esp32h4, fields: [
        EfuseDefinition(name: "WR_DIS", idfName: "WR_DIS", aliases: [], block: 0, bits: [Bits(0, 32)], description: "Disable programming of individual eFuses", category: "config", type: "uint:32", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "RD_DIS", idfName: "RD_DIS", aliases: [], block: 0, bits: [Bits(32, 7)], description: "Disable reading from BlOCK4-10", category: "config", type: "uint:7", inSummary: true, writeDisableBit: 0, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_JTAG", idfName: "DIS_USB_JTAG", aliases: [], block: 0, bits: [Bits(39, 1)], description: "Represents whether the function of usb switch to jtag is disabled or enabled. 1: disabled 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_FORCE_DOWNLOAD", idfName: "DIS_FORCE_DOWNLOAD", aliases: [], block: 0, bits: [Bits(41, 1)], description: "Represents whether the function that forces chip into download mode is disabled or enabled. 1: disabled 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SPI_DOWNLOAD_MSPI_DIS", idfName: "SPI_DOWNLOAD_MSPI_DIS", aliases: [], block: 0, bits: [Bits(42, 1)], description: "Represents whether SPI0 controller during boot_mode_download is disabled or enabled. 1: disabled 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_TWAI", idfName: "DIS_TWAI", aliases: [], block: 0, bits: [Bits(43, 1)], description: "Represents whether TWAI function is disabled or enabled. 1: disabled 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "JTAG_SEL_ENABLE", idfName: "JTAG_SEL_ENABLE", aliases: [], block: 0, bits: [Bits(44, 1)], description: "Represents whether the selection between usb_to_jtag and pad_to_jtag through strapping gpio15 when both EFUSE_DIS_PAD_JTAG and EFUSE_DIS_USB_JTAG are equal to 0 is enabled or disabled. 1: enabled 0: disabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_PAD_JTAG", idfName: "DIS_PAD_JTAG", aliases: [], block: 0, bits: [Bits(45, 1)], description: "Represents whether JTAG is disabled in the hard way(permanently). 1: disabled 0: enabled", category: "jtag", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MANUAL_ENCRYPT", idfName: "DIS_DOWNLOAD_MANUAL_ENCRYPT", aliases: [], block: 0, bits: [Bits(46, 1)], description: "Represents whether flash encrypt function is disabled or enabled(except in SPI boot mode). 1: disabled 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 2, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_GLITCH_EN", idfName: "PVT_GLITCH_EN", aliases: [], block: 0, bits: [Bits(50, 1)], description: "Represents whether to enable PVT power glitch monitor function.1:Enable. 0:Disable", category: "config", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_GLITCH_MODE", idfName: "PVT_GLITCH_MODE", aliases: [], block: 0, bits: [Bits(52, 2)], description: "Use to configure glitch mode", category: "config", type: "uint:2", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_CORE1", idfName: "DIS_CORE1", aliases: [], block: 0, bits: [Bits(54, 1)], description: "Represents whether the CPU-Core1 is disabled.  1: Disabled.  0: Not disable", category: "config", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SPI_BOOT_CRYPT_CNT", idfName: "SPI_BOOT_CRYPT_CNT", aliases: [], block: 0, bits: [Bits(55, 3)], description: "Enables flash encryption when 1 or 3 bits are set and disables otherwise", category: "security", type: "uint:3", inSummary: true, writeDisableBit: 4, readDisableBit: nil, values: [0: "Disable", 1: "Enable", 3: "Disable", 7: "Enable"]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE0", idfName: "SECURE_BOOT_KEY_REVOKE0", aliases: [], block: 0, bits: [Bits(58, 1)], description: "Revoke 1st secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 5, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE1", idfName: "SECURE_BOOT_KEY_REVOKE1", aliases: [], block: 0, bits: [Bits(59, 1)], description: "Revoke 2nd secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 6, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_KEY_REVOKE2", idfName: "SECURE_BOOT_KEY_REVOKE2", aliases: [], block: 0, bits: [Bits(60, 1)], description: "Revoke 3rd secure boot key", category: "security", type: "bool", inSummary: true, writeDisableBit: 7, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_0", idfName: "KEY_PURPOSE_0", aliases: ["KEY0_PURPOSE"], block: 0, bits: [Bits(64, 5)], description: "Represents the purpose of Key0", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 8, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_1", idfName: "KEY_PURPOSE_1", aliases: ["KEY1_PURPOSE"], block: 0, bits: [Bits(69, 5)], description: "Represents the purpose of Key1", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 9, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_2", idfName: "KEY_PURPOSE_2", aliases: ["KEY2_PURPOSE"], block: 0, bits: [Bits(74, 5)], description: "Represents the purpose of Key2", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 10, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_3", idfName: "KEY_PURPOSE_3", aliases: ["KEY3_PURPOSE"], block: 0, bits: [Bits(79, 5)], description: "Represents the purpose of Key3", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 11, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_4", idfName: "KEY_PURPOSE_4", aliases: ["KEY4_PURPOSE"], block: 0, bits: [Bits(84, 5)], description: "Represents the purpose of Key4", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 12, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KEY_PURPOSE_5", idfName: "KEY_PURPOSE_5", aliases: ["KEY5_PURPOSE"], block: 0, bits: [Bits(89, 5)], description: "Represents the purpose of Key5", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 13, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SEC_DPA_LEVEL", idfName: "SEC_DPA_LEVEL", aliases: [], block: 0, bits: [Bits(94, 2)], description: "Represents the spa secure level by configuring the clock random divide mode", category: "security", type: "uint:2", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "XTS_DPA_PSEUDO_LEVEL", idfName: "XTS_DPA_PSEUDO_LEVEL", aliases: [], block: 0, bits: [Bits(96, 2)], description: "Represents the pseudo round level of xts-aes anti-dpa attack. 3: High. 2: Moderate 1. Low 0: Disabled", category: "security", type: "uint:2", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "XTS_DPA_CLK_ENABLE", idfName: "XTS_DPA_CLK_ENABLE", aliases: [], block: 0, bits: [Bits(98, 1)], description: "Represents whether xts-aes anti-dpa attack clock is enabled. 1. Enable. 0: Disable.", category: "security", type: "bool", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ECC_FORCE_CONST_TIME", idfName: "ECC_FORCE_CONST_TIME", aliases: [], block: 0, bits: [Bits(99, 1)], description: "Represents whether to force ecc to use const-time calculation mode.  1: Enable.  0: Disable", category: "config", type: "bool", inSummary: true, writeDisableBit: 14, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ECDSA_P384_ENABLE", idfName: "ECDSA_P384_ENABLE", aliases: [], block: 0, bits: [Bits(100, 1)], description: "Represents if the chip supports ECDSA P384", category: "security", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_EN", idfName: "SECURE_BOOT_EN", aliases: [], block: 0, bits: [Bits(101, 1)], description: "Represents whether secure boot is enabled or disabled. 1: enabled 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 15, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_BOOT_AGGRESSIVE_REVOKE", idfName: "SECURE_BOOT_AGGRESSIVE_REVOKE", aliases: [], block: 0, bits: [Bits(102, 1)], description: "Represents whether revoking aggressive secure boot is enabled or disabled. 1: enabled. 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 16, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_DISABLE_DEPLOY_MODE", idfName: "KM_DISABLE_DEPLOY_MODE", aliases: [], block: 0, bits: [Bits(103, 5)], description: "Represents whether the new key deployment of key manager is disabled. Bit0: Represents whether the new ECDSA key deployment is disabled0: Enabled1: DisabledBit1: Represents whether the new XTS-AES (flash and PSRAM) key deployment is disabled0: Enabled1: DisabledBit2: Represents whether the new HMAC key deployment is disabled0: Enabled1: DisabledBit3: Represents whether the new DS key deployment is disabled0: Enabled1: Disabled", category: "config", type: "uint:5", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_RND_SWITCH_CYCLE", idfName: "KM_RND_SWITCH_CYCLE", aliases: [], block: 0, bits: [Bits(108, 2)], description: "Represents the cycle at which the Key Manager switches random numbers.0: Controlled by the \\hyperref[fielddesc:KEYMNGRNDSWITCHCYCLE]{KEYMNG\\_RND\\_SWITCH\\_CYCLE} register. For more information; please refer to Chapter \\ref{mod:keymng} \\textit{\\nameref{mod:keymng}}1: 8 Key Manager clock cycles2: 16 Key Manager clock cycles3: 32 Key Manager clock cycles", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_DEPLOY_ONLY_ONCE", idfName: "KM_DEPLOY_ONLY_ONCE", aliases: [], block: 0, bits: [Bits(110, 5)], description: "Represents whether the corresponding key can be deployed only once.Bit0: Represents whether the ECDSA key can be deployed only once0: The key can be deployed multiple times1: The key can be deployed only onceBit1: Represents whether the XTS-AES (flash and PSRAM) key can be deployed only once0: The key can be deployed multiple times1: The key can be deployed only onceBit2: Represents whether the HMAC key can be deployed only once0: The key can be deployed multiple times1: The key can be deployed only onceBit3: Represents whether the DS key can be deployed only once0: The key can be deployed multiple times1: The key can be deployed only once", category: "config", type: "uint:5", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_USE_KEY_MANAGER_KEY", idfName: "FORCE_USE_KEY_MANAGER_KEY", aliases: [], block: 0, bits: [Bits(115, 5)], description: "Represents whether the corresponding key must come from Key Manager. Bit0: Represents whether the ECDSA key must come from Key Manager.0: The key does not need to come from Key Manager1: The key must come from Key ManagerBit1: Represents whether the XTS-AES (flash and PSRAM) key must come from Key Manager.0: The key does not need to come from Key Manager1: The key must come from Key ManagerBit2: Represents whether the HMAC key must come from Key Manager.0: The key does not need to come from Key Manager1: The key must come from Key ManagerBit3: Represents whether the DS key must come from Key Manager.0: The key does not need to come from Key Manager1: The key must come from Key Manager", category: "security", type: "uint:5", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_DISABLE_SW_INIT_KEY", idfName: "FORCE_DISABLE_SW_INIT_KEY", aliases: [], block: 0, bits: [Bits(120, 1)], description: "Represents whether to disable the use of the initialization key written by software and instead force use efuse\\_init\\_key.0: Enable1: Disable", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "KM_XTS_KEY_LENGTH_256", idfName: "KM_XTS_KEY_LENGTH_256", aliases: [], block: 0, bits: [Bits(121, 1)], description: "Represents which key flash encryption uses.0: XTS-AES-256 key1: XTS-AES-128 key", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "LOCK_KM_KEY", idfName: "LOCK_KM_KEY", aliases: [], block: 0, bits: [Bits(122, 1)], description: "Represents whether the keys in the Key Manager are locked after deployment.0: Not locked1: Locked", category: "security", type: "bool", inSummary: true, writeDisableBit: 1, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_TPUW", idfName: "FLASH_TPUW", aliases: [], block: 0, bits: [Bits(123, 3)], description: "Represents the flash waiting time after power-up; in unit of ms. When the value less than 15; the waiting time is the programmed value. Otherwise; the waiting time is 2 times the programmed value", category: "flash", type: "uint:3", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DOWNLOAD_MODE", idfName: "DIS_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(127, 1)], description: "Represents whether Download mode is disabled or enabled. 1: disabled 0: enabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_DIRECT_BOOT", idfName: "DIS_DIRECT_BOOT", aliases: [], block: 0, bits: [Bits(128, 1)], description: "Represents whether direct boot mode is disabled or enabled. 1: disabled 0: enabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_ROM_PRINT", idfName: "DIS_USB_SERIAL_JTAG_ROM_PRINT", aliases: [], block: 0, bits: [Bits(129, 1)], description: "Represents whether print from USB-Serial-JTAG is disabled or enabled. 1: disabled 0: enabled", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", idfName: "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE", aliases: [], block: 0, bits: [Bits(130, 1)], description: "Represents whether the USB-Serial-JTAG download function is disabled or enabled. 1: Disable 0: Enable", category: "usb", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "ENABLE_SECURITY_DOWNLOAD", idfName: "ENABLE_SECURITY_DOWNLOAD", aliases: [], block: 0, bits: [Bits(131, 1)], description: "Represents whether security download is enabled or disabled. 1: enabled 0: disabled", category: "security", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "UART_PRINT_CONTROL", idfName: "UART_PRINT_CONTROL", aliases: [], block: 0, bits: [Bits(132, 2)], description: "Represents the type of UART printing. 00: force enable printing 01: enable printing when GPIO8 is reset at low level 10: enable printing when GPIO8 is reset at high level 11: force disable printing", category: "config", type: "uint:2", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FORCE_SEND_RESUME", idfName: "FORCE_SEND_RESUME", aliases: [], block: 0, bits: [Bits(134, 1)], description: "Represents whether ROM code is forced to send a resume command during SPI boot. 1: forced 0:not forced", category: "flash", type: "bool", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SECURE_VERSION", idfName: "SECURE_VERSION", aliases: [], block: 0, bits: [Bits(135, 16)], description: "Represents the version used by ESP-IDF anti-rollback feature", category: "security", type: "uint:16", inSummary: true, writeDisableBit: 18, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "HUK_GEN_STATE", idfName: "HUK_GEN_STATE", aliases: [], block: 0, bits: [Bits(151, 5)], description: "Represents whether the HUK generate mode is valid.Odd count of bits with a value of 1: InvalidEven count of bits with a value of 1: Valid", category: "config", type: "uint:5", inSummary: true, writeDisableBit: 19, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_LDO_EFUSE_SEL", idfName: "FLASH_LDO_EFUSE_SEL", aliases: [], block: 0, bits: [Bits(156, 1)], description: "Represents whether to select efuse control flash ldo default voltage.  1 : efuse 0 : strapping", category: "flash", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_EXCHG_PINS", idfName: "USB_EXCHG_PINS", aliases: [], block: 0, bits: [Bits(168, 1)], description: "Represents whether the D+ and D- pins of USB_SERIAL_JTAG PHY is exchanged. 1: exchanged 0: not exchanged", category: "usb", type: "bool", inSummary: true, writeDisableBit: 30, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_OTG_FS_EXCHG_PINS", idfName: "USB_OTG_FS_EXCHG_PINS", aliases: [], block: 0, bits: [Bits(169, 1)], description: "Represents whether the D+ and D- pins of USB_OTG_FS PHY is exchanged. 1: exchanged 0: not exchanged", category: "usb", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "USB_PHY_SEL", idfName: "USB_PHY_SEL", aliases: [], block: 0, bits: [Bits(170, 1)], description: "Represents whether to exchange the USB_SERIAL_JTAG PHY with USB_OTG_FS PHY.  1: exchanged.  0: not exchanged", category: "usb", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "SOFT_DIS_JTAG", idfName: "SOFT_DIS_JTAG", aliases: [], block: 0, bits: [Bits(171, 3)], description: "Represents whether JTAG is disabled in soft way. Odd number: disabled Even number: enabled", category: "jtag", type: "uint:3", inSummary: true, writeDisableBit: 31, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "IO_LDO_ADJUST", idfName: "IO_LDO_ADJUST", aliases: [], block: 0, bits: [Bits(174, 8)], description: "Represents configuration of IO LDO mode and voltage.", category: "config", type: "uint:8", inSummary: false, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "IO_LDO_1P8", idfName: "IO_LDO_1P8", aliases: [], block: 0, bits: [Bits(182, 1)], description: "Represents select IO LDO voltage to 1.8V or 3.3V. 1: 1.8V 0: 3.3V", category: "config", type: "bool", inSummary: false, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "DCDC_CCM_EN", idfName: "DCDC_CCM_EN", aliases: [], block: 0, bits: [Bits(183, 1)], description: "Represents whether change DCDC to CCM mode", category: "config", type: "bool", inSummary: true, writeDisableBit: nil, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "MAC", idfName: "MAC", aliases: ["MAC_FACTORY"], block: 1, bits: [Bits(40, 8), Bits(32, 8), Bits(24, 8), Bits(16, 8), Bits(8, 8), Bits(0, 8)], description: "MAC address", category: "MAC", type: "bytes:6", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "MAC_EXT", idfName: "MAC_EXT", aliases: [], block: 1, bits: [Bits(56, 8), Bits(48, 8)], description: "Stores the extended bits of MAC address", category: "MAC", type: "bytes:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_LIMIT", idfName: "PVT_LIMIT", aliases: [], block: 1, bits: [Bits(64, 16)], description: "Power glitch monitor threthold", category: "config", type: "uint:16", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_CELL_SELECT", idfName: "PVT_CELL_SELECT", aliases: [], block: 1, bits: [Bits(80, 7)], description: "Power glitch monitor PVT cell select", category: "config", type: "uint:7", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_PUMP_LIMIT", idfName: "PVT_PUMP_LIMIT", aliases: [], block: 1, bits: [Bits(87, 8)], description: "Use to configure voltage monitor limit for charge pump", category: "config", type: "uint:8", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PUMP_DRV", idfName: "PUMP_DRV", aliases: [], block: 1, bits: [Bits(96, 4)], description: "Use to configure charge pump voltage gain", category: "config", type: "uint:4", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "WDT_DELAY_SEL", idfName: "WDT_DELAY_SEL", aliases: [], block: 1, bits: [Bits(100, 2)], description: "Represents the threshold level of the RTC watchdog STG0 timeout. 0: Original threshold configuration value of STG0 *2 1: Original threshold configuration value of STG0 *4 2: Original threshold configuration value of STG0 *8 3: Original threshold configuration value of STG0 *16", category: "wdt", type: "uint:2", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "HYS_EN_PAD", idfName: "HYS_EN_PAD", aliases: [], block: 1, bits: [Bits(102, 1)], description: "Represents whether the hysteresis function of corresponding PAD is enabled. 1: enabled 0:disabled", category: "config", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "PVT_GLITCH_CHARGE_RESET", idfName: "PVT_GLITCH_CHARGE_RESET", aliases: [], block: 1, bits: [Bits(103, 1)], description: "Represents whether to trigger reset or charge pump when PVT power glitch happened.1:Trigger charge pump. 0:Trigger reset", category: "config", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "VDD_SPI_LDO_ADJUST", idfName: "VDD_SPI_LDO_ADJUST", aliases: [], block: 1, bits: [Bits(105, 8)], description: "Represents configuration of FLASH LDO mode and voltage.", category: "vdd", type: "uint:8", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
        EfuseDefinition(name: "FLASH_LDO_POWER_SEL", idfName: "FLASH_LDO_POWER_SEL", aliases: [], block: 1, bits: [Bits(113, 1)], description: "Represents which flash ldo be select: 1: FLASH LDO 1P2 0 : FLASH LDO 1P8", category: "flash", type: "bool", inSummary: true, writeDisableBit: 20, readDisableBit: nil, values: [:]),
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
    public enum ESP32H4 {
        public static let blockKey0: EfuseFieldName = "BLOCK_KEY0"
        public static let blockKey1: EfuseFieldName = "BLOCK_KEY1"
        public static let blockKey2: EfuseFieldName = "BLOCK_KEY2"
        public static let blockKey3: EfuseFieldName = "BLOCK_KEY3"
        public static let blockKey4: EfuseFieldName = "BLOCK_KEY4"
        public static let blockKey5: EfuseFieldName = "BLOCK_KEY5"
        public static let blockSysData2: EfuseFieldName = "BLOCK_SYS_DATA2"
        public static let blockUsrData: EfuseFieldName = "BLOCK_USR_DATA"
        public static let customMac: EfuseFieldName = "CUSTOM_MAC"
        public static let dcdcCcmEn: EfuseFieldName = "DCDC_CCM_EN"
        public static let disCore1: EfuseFieldName = "DIS_CORE1"
        public static let disDirectBoot: EfuseFieldName = "DIS_DIRECT_BOOT"
        public static let disDownloadManualEncrypt: EfuseFieldName = "DIS_DOWNLOAD_MANUAL_ENCRYPT"
        public static let disDownloadMode: EfuseFieldName = "DIS_DOWNLOAD_MODE"
        public static let disForceDownload: EfuseFieldName = "DIS_FORCE_DOWNLOAD"
        public static let disPadJtag: EfuseFieldName = "DIS_PAD_JTAG"
        public static let disTwai: EfuseFieldName = "DIS_TWAI"
        public static let disUsbJtag: EfuseFieldName = "DIS_USB_JTAG"
        public static let disUsbSerialJtagDownloadMode: EfuseFieldName = "DIS_USB_SERIAL_JTAG_DOWNLOAD_MODE"
        public static let disUsbSerialJtagRomPrint: EfuseFieldName = "DIS_USB_SERIAL_JTAG_ROM_PRINT"
        public static let eccForceConstTime: EfuseFieldName = "ECC_FORCE_CONST_TIME"
        public static let ecdsaP384Enable: EfuseFieldName = "ECDSA_P384_ENABLE"
        public static let enableSecurityDownload: EfuseFieldName = "ENABLE_SECURITY_DOWNLOAD"
        public static let flashLdoEfuseSel: EfuseFieldName = "FLASH_LDO_EFUSE_SEL"
        public static let flashLdoPowerSel: EfuseFieldName = "FLASH_LDO_POWER_SEL"
        public static let flashTpuw: EfuseFieldName = "FLASH_TPUW"
        public static let forceDisableSwInitKey: EfuseFieldName = "FORCE_DISABLE_SW_INIT_KEY"
        public static let forceSendResume: EfuseFieldName = "FORCE_SEND_RESUME"
        public static let forceUseKeyManagerKey: EfuseFieldName = "FORCE_USE_KEY_MANAGER_KEY"
        public static let hukGenState: EfuseFieldName = "HUK_GEN_STATE"
        public static let hysEnPad: EfuseFieldName = "HYS_EN_PAD"
        public static let ioLdo1p8: EfuseFieldName = "IO_LDO_1P8"
        public static let ioLdoAdjust: EfuseFieldName = "IO_LDO_ADJUST"
        public static let jtagSelEnable: EfuseFieldName = "JTAG_SEL_ENABLE"
        public static let keyPurpose0: EfuseFieldName = "KEY_PURPOSE_0"
        public static let keyPurpose1: EfuseFieldName = "KEY_PURPOSE_1"
        public static let keyPurpose2: EfuseFieldName = "KEY_PURPOSE_2"
        public static let keyPurpose3: EfuseFieldName = "KEY_PURPOSE_3"
        public static let keyPurpose4: EfuseFieldName = "KEY_PURPOSE_4"
        public static let keyPurpose5: EfuseFieldName = "KEY_PURPOSE_5"
        public static let kmDeployOnlyOnce: EfuseFieldName = "KM_DEPLOY_ONLY_ONCE"
        public static let kmDisableDeployMode: EfuseFieldName = "KM_DISABLE_DEPLOY_MODE"
        public static let kmRndSwitchCycle: EfuseFieldName = "KM_RND_SWITCH_CYCLE"
        public static let kmXtsKeyLength256: EfuseFieldName = "KM_XTS_KEY_LENGTH_256"
        public static let lockKmKey: EfuseFieldName = "LOCK_KM_KEY"
        public static let mac: EfuseFieldName = "MAC"
        public static let macEui64: EfuseFieldName = "MAC_EUI64"
        public static let macExt: EfuseFieldName = "MAC_EXT"
        public static let pumpDrv: EfuseFieldName = "PUMP_DRV"
        public static let pvtCellSelect: EfuseFieldName = "PVT_CELL_SELECT"
        public static let pvtGlitchChargeReset: EfuseFieldName = "PVT_GLITCH_CHARGE_RESET"
        public static let pvtGlitchEn: EfuseFieldName = "PVT_GLITCH_EN"
        public static let pvtGlitchMode: EfuseFieldName = "PVT_GLITCH_MODE"
        public static let pvtLimit: EfuseFieldName = "PVT_LIMIT"
        public static let pvtPumpLimit: EfuseFieldName = "PVT_PUMP_LIMIT"
        public static let rdDis: EfuseFieldName = "RD_DIS"
        public static let secureBootAggressiveRevoke: EfuseFieldName = "SECURE_BOOT_AGGRESSIVE_REVOKE"
        public static let secureBootEn: EfuseFieldName = "SECURE_BOOT_EN"
        public static let secureBootKeyRevoke0: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE0"
        public static let secureBootKeyRevoke1: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE1"
        public static let secureBootKeyRevoke2: EfuseFieldName = "SECURE_BOOT_KEY_REVOKE2"
        public static let secureVersion: EfuseFieldName = "SECURE_VERSION"
        public static let secDpaLevel: EfuseFieldName = "SEC_DPA_LEVEL"
        public static let softDisJtag: EfuseFieldName = "SOFT_DIS_JTAG"
        public static let spiBootCryptCnt: EfuseFieldName = "SPI_BOOT_CRYPT_CNT"
        public static let spiDownloadMspiDis: EfuseFieldName = "SPI_DOWNLOAD_MSPI_DIS"
        public static let uartPrintControl: EfuseFieldName = "UART_PRINT_CONTROL"
        public static let usbExchgPins: EfuseFieldName = "USB_EXCHG_PINS"
        public static let usbOtgFsExchgPins: EfuseFieldName = "USB_OTG_FS_EXCHG_PINS"
        public static let usbPhySel: EfuseFieldName = "USB_PHY_SEL"
        public static let vddSpiLdoAdjust: EfuseFieldName = "VDD_SPI_LDO_ADJUST"
        public static let wdtDelaySel: EfuseFieldName = "WDT_DELAY_SEL"
        public static let wrDis: EfuseFieldName = "WR_DIS"
        public static let xtsDpaClkEnable: EfuseFieldName = "XTS_DPA_CLK_ENABLE"
        public static let xtsDpaPseudoLevel: EfuseFieldName = "XTS_DPA_PSEUDO_LEVEL"
    }
}
