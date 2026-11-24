# ``ESPTargets``

Base types shared by every ESPKit module: chip families, revisions, MAC addresses, flash settings and regions.

## Overview

ESPTargets has no I/O and no dependency. Every other module builds on it, so its types are the
common vocabulary of the SDK: a ``ChipFamily`` says which chip you talk to, a ``FlashRegion``
says what to write where, ``FlashHeaderOverrides`` says how to patch a bootloader header on
the way.

```swift
import ESPTargets

let chip = ChipFamily.esp32s3
print(chip.displayName, chip.architecture, String(chip.bootloaderOffset, radix: 16))
// ESP32-S3 xtensa 0

let mac = MACAddress("24:0A:C4:12:34:56")!
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
