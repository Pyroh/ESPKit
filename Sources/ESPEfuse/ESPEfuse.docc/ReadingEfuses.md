# Reading eFuses

Decode fields, inspect blocks, and work without a chip.

## Overview

``EfuseController/init(device:)`` reads every block through the chip's registers, under the ROM
or the stub. ESPKit knows the registers of the ESP32 and ESP32-S3; other chips throw
``EfuseError/unsupportedChip(_:)`` for now, although their tables are available virtually.

- ``EfuseController/fields()`` returns every field, with its raw ``EfuseField/value`` and the
  presentation espefuse uses in ``EfuseField/displayValue`` (named values, converted calibration,
  MAC with its CRC).
- ``EfuseController/field(_:)`` returns one field by name.
- ``EfuseController/blocks()`` returns the raw words of each block.
- ``EfuseController/codingErrors()`` reports what the controller's error-correction found
  (Reed-Solomon on recent chips, repeat coding in BLOCK0, 3/4 coding on the ESP32).
- ``EfuseController/adcCalibration()`` converts the ADC calibration like `espefuse adc-info`.
- ``EfuseController/customMAC()`` returns the custom MAC address, if one is programmed.

```swift
let efuses = try await EfuseController(device: esp)
if let counter = await efuses.field(EfuseFieldName.ESP32S3.spiBootCryptCnt) {
    print("SPI_BOOT_CRYPT_CNT =", counter.displayValue)
}
let json = await efuses.summaryJSON()          // same bytes as espefuse summary --format json
```

A read-protected block (a secret key) reads back as zeros, and its byte fields show `??`, as in
espefuse.

### Without a chip

``EfuseController/init(virtual:initialState:)`` simulates a controller: blank, or filled from an
``EfuseSnapshot`` (for example rebuilt from an `espefuse dump`). It is the place to try a burn
plan. ``EfuseController/snapshot()`` and ``EfuseController/token()`` save a state;
``EfuseController/init(token:)`` reopens it read-only.
