# Field Names

Name fields with generated constants, or with plain strings.

## Overview

Every chip's fields are available as constants, generated from ESP-IDF's tables and documented
with the field's description:

```swift
let name = EfuseFieldName.ESP32S3.spiBootCryptCnt      // "SPI_BOOT_CRYPT_CNT"
let same: EfuseFieldName = "SPI_BOOT_CRYPT_CNT"
```

A plain string works too, with the ESP-IDF name or an espefuse alias, so a field missing from the
generated tables can still be read. Constants exist for the ESP32, ESP32-S2, S3, C2, C3, C5, C6,
C61, H2, H21, H4 and P4, in the namespaces of ``EfuseFieldName``.
