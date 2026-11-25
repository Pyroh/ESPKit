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

- images built by ``ImageBuilder`` and files produced by ``MergedImage`` are identical to esptool 4.11
  and 5.1 on ESP-IDF, Arduino and ESP8266 builds;
- Secure Boot v2 signatures verify with `espsecure verify-signature`; key digests, Secure Boot v1
  digests and flash encryption match espsecure;
- `summaryJSON()` matches `espefuse summary --format json` on real boards, and virtual burn
  scenarios end in the same state as `espefuse --virt`.

The scripts in `Tools/oracle` produce the references; `TESTING.md` at the root of the repository
explains how to run every test, on a simulated chip, against the tools and on real boards.

### Licence

ESPKit is dual-licensed MIT OR Apache-2.0. It contains no esptool, espefuse or espsecure code
(GPL); protocol constants, register addresses and timings are technical facts documented by
Espressif. The bundled stub is esp-flasher-stub (MIT OR Apache-2.0) and the eFuse tables derive
from ESP-IDF (Apache-2.0). See `NOTICE`.

### Disclaimer

ESPKit is provided "as is", without warranty of any kind, express or implied, as its licences
(MIT and Apache-2.0) state. It writes flash memory and can burn eFuses, which cannot be undone: a
wrong write, an interrupted transfer or a wrong eFuse can leave a board unusable or permanently
locked. You use it at your own risk; the authors and contributors are not liable for damaged,
bricked or locked hardware, lost data, or any other damage.

Bug reports are welcome, though: open an issue at <https://github.com/Pyroh/ESPKit/issues> with the
chip, the board and USB adapter, the ESPKit commit and, when the problem involves the chip, a trace
(`ConnectOptions.trace`).

ESPKit is an independent project, not affiliated with, endorsed or supported by Espressif Systems.
Product names are trademarks of their respective owners.
