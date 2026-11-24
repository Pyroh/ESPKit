# ``ESPEfuse``

Read, decode and burn eFuses: the equivalent of `espefuse`.

## Overview

eFuses are one-time programmable bits that hold a chip's MAC addresses, calibration, security
settings and keys. ESPEfuse decodes them with tables generated from ESP-IDF's eFuse CSV files, and
presents them as espefuse does: ``EfuseController/summaryJSON()`` is byte-identical to
`espefuse summary --format json` on the ESP32 and ESP32-S3.

```swift
import ESPDevice
import ESPEfuse

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")
let efuses = try await EfuseController(device: esp)
for field in await efuses.fields() where field.category == "security" {
    print(field.name, field.displayValue)
}
```

Burning is irreversible, so it goes through a plan you can check first, virtually or with
``EfuseController/preview(_:)``, before an explicit ``EfuseController/burn(_:confirm:)``.

## Topics

### Essentials

- <doc:ReadingEfuses>
- <doc:BurningEfuses>
- <doc:FieldNames>

### Controller

- ``EfuseController``
- ``EfuseSnapshot``

### Fields and blocks

- ``EfuseFieldName``
- ``EfuseField``
- ``EfuseValue``
- ``EfuseBlock``
- ``EfuseCodingError``
- ``ADCCalibration``

### Burning

- ``EfuseBurnPlan``
- ``KeyBlock``
- ``FlashVoltage``
- ``BurnConfirmation``
- ``EfuseChange``
- ``EfusePlanIssue``
- ``EfuseBurnReport``

### Errors

- ``EfuseError``
