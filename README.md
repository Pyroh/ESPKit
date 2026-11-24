# ESPKit

A Swift SDK for talking to the serial bootloader of Espressif chips (ESP8266, ESP32 and the ESP32-x family): detection, flashing, images, Secure Boot, flash encryption and eFuses. An independent reimplementation of what esptool, espefuse and espsecure can do, without a CLI.

- **Platforms:** macOS 15+ and Linux.
- **Language:** Swift 6.2 or later (swift-crypto 5.1), strict concurrency. `ESPDevice` is an `actor`; long-running operations are `AsyncSequence`s.
- **License:** MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`).

The public API specification is the reference; it lives in the research folder (`ESPKit-API.md`).

## Status: phase 5, virtual only (eFuse programming)

Available:

- base types (`ChipFamily`, `ChipRevision`, `MACAddress`, `KeyPurpose`, flash settings);
- POSIX `SerialPort` with arbitrary baud rates (macOS: IOSSIOSPEED; Linux: termios2), port discovery (IOKit, sysfs), reset sequences (classic, UnixTight, USB-Serial-JTAG, custom);
- connection: reset, sync, chip detection (chip ID or magic value), Secure Download Mode;
- bundled v2 stub (`esp-flasher-stub` 2.0.0, every chip except the ESP32-E22), baud rate change;
- flash: zlib-compressed writes with MD5 check, bootloader header patching, read, verify, full or ranged erase;
- long-running operations as `AsyncSequence` (`ESPOperation`): progress, cancellation;
- images (`ESPImage`, no I/O): ELF reading, `elf2image` (ESP32-x and ESP8266 v1/v2), image reading and validation (`image-info`), raw, Intel HEX and UF2 merging, Intel HEX reading. Output is byte-identical to esptool 4.11 and 5.1 on ESP-IDF and Arduino builds;
- registers, MAC, `securityInfo()`, JEDEC identity, raw SPI commands;
- low-level tracing (`ConnectOptions.trace`).

```swift
import ESPKit

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")   // v2 stub, 460,800 baud
let regions = [
    FlashRegion(address: esp.chip.bootloaderOffset, data: try Data(contentsOf: bootloader)),
    FlashRegion(address: 0x8000, data: try Data(contentsOf: partitions)),
    FlashRegion(address: 0x10000, data: try Data(contentsOf: firmware)),
]
for try await event in esp.writeFlash(regions) {
    if case .progress(let p) = event { print(p.stage, Int(p.fractionCompleted * 100), "%") }
}
await esp.disconnect(.hard)
```

- security (`ESPSecure`, no I/O): Secure Boot v2 with RSA-3072, ECDSA P-256 and P-384 (PEM key generation and loading, local signing or through an external `Signer`, up to 3 signature blocks, verification, key digest to burn into eFuses); XTS-AES-128 and 256 flash encryption and the ESP32 scheme, byte-identical to espsecure. Images signed by ESPKit are accepted by `espsecure verify-signature`.

- eFuses (`ESPEfuse`): tables for 12 chips generated from ESP-IDF, block reading on the ESP32 and ESP32-S3, decoded fields (named values, key purposes, MAC, protections), coding errors, ADC calibration, snapshots and tokens, virtual controller. `summaryJSON()` is byte-identical to `espefuse summary --format json` on the ESP32 and ESP32-S3.

- eFuse programming, **virtual only**: plan (`EfuseBurnPlan`: fields, keys, Secure Boot digests, block data, bits, protections, custom MAC, flash voltage), preview, burning from the last block down to BLOCK0 with the lock bits last. The scenarios produce the same state as `espefuse --virt`, byte for byte. On a real chip, `burn` refuses: the hardware sequence is not written yet.

Not yet: programming on a board (phase 5, on a sacrificial board), encrypted writes, differential reflashing, NAND and the rest (phase 6).

## Tests

```bash
swift test
```

Hardware tests are skipped by default. To run them (chip identity):

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
```

The flash test also needs a PlatformIO build whose application prints `ESPKit HIL OK <chip>` on its console (`printf("ESPKit HIL OK %s\n", CONFIG_IDF_TARGET)` under ESP-IDF):

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_FIRMWARE_ESP32=…/.pio/build/esp32 swift test --filter HardwareTests
```

The `ESPImage` differential tests compare ESPKit with esptool, used as a black box. `Tools/oracle/make-references.sh` produces the reference binaries from ESP-IDF, Arduino and ESP8266 builds (see the script header), then:

```bash
ESPKIT_IMAGE_REFERENCES=…/ref-v5 swift test --filter ReferenceTests
```

For `ESPSecure`, `Tools/oracle/make-secure-references.sh` produces reference keys, signatures and ciphertexts with espsecure, then:

```bash
ESPKIT_SECURE_REFERENCES=… ESPKIT_ESPSECURE=espsecure swift test --filter ESPSecureTests
```

For `ESPEfuse`, `Tools/oracle/make-efuse-references.sh` uses espefuse (read only) to record the labels of every chip and, when boards are connected, their summaries and dumps. The tables are then regenerated from ESP-IDF:

```bash
python3 -I Tools/efuse-codegen/generate.py <esp-idf>/components/efuse <references>/real <references>/virt
ESPKIT_EFUSE_REFERENCES=<references> swift test --filter ESPEfuseTests
```

The programming scenarios are replayed with `Tools/oracle/make-burn-references.sh` (espefuse `--virt`, no chip touched), then `ESPKIT_BURN_REFERENCES=<folder> swift test --filter ESPEfuseTests`.

The bundled stub is regenerated from an esp-flasher-stub release:

```bash
python3 -I Tools/generate-stubs.py v2.0.0 <folder of downloaded JSON files>
```

## Contribution rules

- Code is written from the specification and public documentation, never by translating esptool's Python (GPL).
- Every file carries the `// SPDX-License-Identifier: MIT OR Apache-2.0` header.
- Accepted dependencies: `swift-crypto` (5.1.x), system libz (the `zlib1g-dev` package on Linux). Nothing under GPL or LGPL.
