# Correspondence with esptool

Where each esptool, espefuse and espsecure command lives in ESPKit.

## Overview

### esptool

| Command | ESPKit |
|---|---|
| `chip-id`, `read-mac`, `flash-id` | `ESPDevice.chip`, `chipID()`, `macAddress()`, `flashInfo()` |
| `get-security-info` | `ESPDevice.securityInfo()` |
| `write-flash` (`-z`, `-e`, `--diff-with`, `--skip-flashed`, `--encrypt-files`, `--flash-*`) | `writeFlash(_:options:)` with ``WriteFlashOptions`` |
| `read-flash`, `verify-flash` | `readFlash(at:count:)`, `verifyFlash(_:)` |
| `erase-flash`, `erase-region` | `eraseFlash(force:)`, `eraseRegion(at:count:force:)` |
| `read-flash-status`, `write-flash-status`, `read-flash-sfdp` | `readFlashStatus(byteCount:)`, `writeFlashStatus(_:byteCount:nonVolatile:)`, `readSFDP(at:count:)` |
| `read-mem`, `write-mem`, `dump-mem` | `readRegister(_:)`, `writeRegister(_:_:mask:delay:)`, `readMemory(at:count:)` |
| `load-ram`, `run` | `loadRAMAndRun(_:)`, `runFlashApplication()` |
| `elf2image` | `ImageBuilder.makeImage(from:chip:options:)`, `makeESP8266Image(from:version:options:)` |
| `image-info` | `AnyFirmwareImage(parsing:chip:)`, `validate()` |
| `merge-bin` (raw, hex, uf2) | `MergedImage.raw`, `intelHex`, `uf2` |
| `--before`, `--after` | `ConnectOptions.entryReset`, `disconnect(_:)` with ``ExitReset`` |
| `--no-stub`, `--baud`, `--trace` | `ConnectOptions.stub`, `baudRate`, `trace` |

### espefuse

| Command | ESPKit |
|---|---|
| `summary`, `summary --format json` | `EfuseController.fields()`, `summaryJSON()` |
| `dump` | `EfuseController.blocks()` |
| `check-error`, `adc-info` | `codingErrors()`, `adcCalibration()` |
| `burn-efuse`, `burn-bit`, `burn-block-data` | `EfuseBurnPlan.set(_:to:)`, `burnBits(_:in:)`, `writeBlockData(_:to:offset:)` |
| `burn-key`, `burn-key-digest` | `writeKey(_:to:purpose:readProtect:writeProtect:)`, `writeKeyDigest(_:to:purpose:)` |
| `read-protect-efuse`, `write-protect-efuse` | `readProtect(_:)`, `writeProtect(_:)` |
| `burn-custom-mac`, `set-flash-voltage` | `setCustomMAC(_:)`, `setFlashVoltage(_:)` |
| `--virt` | `EfuseController(virtual:initialState:)` |

### espsecure

| Command | ESPKit |
|---|---|
| `generate-signing-key` | `SecureBootV2.SigningKey.generate(_:)` |
| `sign-data`, `verify-signature` (v2) | `SecureBootV2.sign(_:with:appendingTo:)`, `verify(_:publicKey:)` |
| `digest-sbv2-public-key` | `SecureBootV2.PublicKey.digest` |
| `signature-info-v2` | `SecureBootV2.signatureBlocks(in:)` |
| `digest-secure-bootloader`, `digest-private-key`, `sign-data --version 1` | `SecureBootV1.digest`, `derivedKey`, `sign` |
| `generate-flash-encryption-key`, `encrypt-flash-data`, `decrypt-flash-data` | `FlashEncryption.generateKey`, `encrypt`, `decrypt` |

### Not available yet

SPI NAND flash, ECDSA P-192 signatures, the ESP32-S31 Secure Debug Controller, RFC 2217 serial over
the network, and real eFuse burns on chips other than the ESP32.
