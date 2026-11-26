# Chips and Flash Settings

The common vocabulary of the SDK: chip families, revisions, MAC addresses, flash settings and regions.

## Overview

These types come from the ESPTargets module, which has no I/O and no dependency; every other
module builds on it, so they appear everywhere: a ``ChipFamily`` says which chip you talk to, a ``FlashRegion``
says what to write where, ``FlashHeaderOverrides`` says how to patch a bootloader header on
the way.

```swift
import ESPKit

let chip = ChipFamily.esp32s3
print(chip.displayName, chip.architecture, String(chip.bootloaderOffset, radix: 16))
// ESP32-S3 xtensa 0

let mac = MACAddress("24:0A:C4:12:34:56")      // nil if the text is not a MAC address
let firmware = FlashRegion(address: 0x10000, data: try Data(contentsOf: url))
```

Every ESPKit error type conforms to ``ESPKitError``, so a single `catch let error as ESPKitError`
handles them all, with an English `description`.

## Topics

### Chips

- ``ChipFamily``
- ``ChipRevision``

### Identity

- ``MACAddress``
- ``MD5Digest``
- ``KeyPurpose``

### Flash settings

- ``FlashMode``
- ``FlashFrequency``
- ``FlashSize``
- ``FlashType``
- ``SPIConnection``
- ``FlashHeaderOverrides``
- ``HeaderSetting``

### Writing

- ``FlashRegion``

### Errors

- ``ESPKitError``
