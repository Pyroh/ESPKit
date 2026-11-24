# Compatibility and Testing

Which chips are verified, how ESPKit is checked against Espressif's tools, and its licence.

## Overview

### Chips

Every family has a descriptor and a bundled stub (except the ESP32-E22). Verified on real boards:
the ESP32 (through a CH340 bridge) and the ESP32-S3 (through a CH340 and through its native
USB-Serial-JTAG). Other chips are supported from their documentation and checked against esptool's
outputs, without a board.

### Byte-for-byte comparison

ESPKit's tests use Espressif's tools as black boxes and compare outputs, never code:

- images built by `ImageBuilder` and files produced by `MergedImage` are identical to esptool 4.11
  and 5.1 on ESP-IDF, Arduino and ESP8266 builds;
- Secure Boot v2 signatures verify with `espsecure verify-signature`; key digests, Secure Boot v1
  digests and flash encryption match espsecure;
- `summaryJSON()` matches `espefuse summary --format json` on real boards, and virtual burn
  scenarios end in the same state as `espefuse --virt`.

The scripts in `Tools/oracle` produce the references; the README explains how to run the tests.

### Licence

ESPKit is dual-licensed MIT OR Apache-2.0. It contains no esptool, espefuse or espsecure code
(GPL); protocol constants, register addresses and timings are technical facts documented by
Espressif. The bundled stub is esp-flasher-stub (MIT OR Apache-2.0) and the eFuse tables derive
from ESP-IDF (Apache-2.0). See `NOTICE`.
