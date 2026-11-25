# Testing ESPKit

ESPKit is tested at three levels:

1. **Default tests**: no chip, no external tool. They run everywhere, in CI included.
2. **Differential tests**: ESPKit's outputs compared byte for byte with esptool, espsecure and
   espefuse, used as black boxes. They need reference files produced by the scripts in
   `Tools/oracle`.
3. **Hardware tests**: real boards on serial ports. One suite burns eFuses and is
   **irreversible**.

Levels 2 and 3 are skipped unless their environment variables are set, so a plain `swift test`
never touches a board and never needs Espressif's tools.

## Running the tests

```bash
swift test
```

The suites use Swift Testing. Run part of them with `--filter`, which matches target, suite and
test names:

```bash
swift test --filter ESPEfuseTests
```

```bash
swift test --filter "Differential reflash"
```

On macOS, a failed test is marked with an SF Symbols glyph rather than `✘`. To pick out failures
in a long log, read the summary line at the end, or search for `failed`.

### Linux

The package builds and tests the same way on Linux with Swift 6.2 and zlib (`zlib1g-dev`). The
official `swift:6.2` image is enough:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.2 bash -c "apt-get -qq update && apt-get -qq install -y zlib1g-dev && swift test"
```

Hardware tests are not run on Linux yet. Serial port discovery has its own sysfs implementation
there, and it has not been tried against a real board.

### Continuous integration

`.github/workflows/ci.yml` runs `swift build --build-tests` and `swift test` on macOS and in the
`swift:6.2` container on Linux. On macOS it also builds the documentation with warnings as
errors. CI runs only the default tests.

## Default tests

| Target | What it covers |
|---|---|
| `ESPTargetsTests` | Chip families and revisions, MAC addresses, flash settings, header overrides |
| `ESPSupportTests` | MD5, SHA-256 and zlib against known vectors |
| `ESPTransportTests` | `SerialPort` on a pseudo-terminal: arbitrary baud rates, exchanges, missing devices |
| `ESPImageTests` | ELF parsing, `elf2image`, image reading and validation, raw / Intel HEX / UF2 merging |
| `ESPSecureTests` | Secure Boot v1 and v2 (keys, signatures, digests), XTS-AES and ESP32 flash encryption |
| `ESPEfuseTests` | eFuse tables, decoding, coding errors, virtual burns, the ESP32 3/4 coding scheme |
| `ESPDeviceTests` | SLIP and packets, then the whole `ESPDevice` API against a simulated chip |

### The simulated chip

`Tests/ESPDeviceTests/SimulatedChip.swift` is a `Transport` that answers like a chip in download
mode. It plays the ROM bootloader and the flasher stub, with flash, RAM, registers and an eFuse
controller. The `ESPDevice` tests use it to cover the full exchanges without a board:

- connection and sync;
- stub loading and baud rate changes;
- compressed and differential writes, encrypted writes;
- reads, verification and erasure;
- flash status registers and SFDP;
- memory reads and code loaded into RAM;
- eFuse burns on a simulated ESP32, including the read-back that stops at the first unrequested
  bit.

Faults are injected on purpose: corrupted flash writes, eFuse bits that flip, and eFuse programs
that do not take.

## Differential tests

Each suite reads a folder of references produced by one script in `Tools/oracle`. The scripts run
Espressif's tools as commands and keep only their outputs. The references are not stored in the
repository, so regenerate them whenever the tools or the input builds change.

| Variable | Suite | Produced by |
|---|---|---|
| `ESPKIT_IMAGE_REFERENCES` | esptool differential (`ESPImageTests`) | `make-references.sh` |
| `ESPKIT_SECURE_REFERENCES` | espsecure interoperability (`ESPSecureTests`) | `make-secure-references.sh` |
| `ESPKIT_ESPSECURE` | the same suite: espsecure also verifies the images ESPKit signs | (the espsecure command) |
| `ESPKIT_EFUSE_REFERENCES` | espefuse differential (`ESPEfuseTests`), eFuses on a board (`HardwareTests`) | `make-efuse-references.sh` |
| `ESPKIT_BURN_REFERENCES` | burning compared with `espefuse --virt` (`ESPEfuseTests`) | `make-burn-references.sh` |

Each script's header lists what it needs. In short:

### Images: esptool

The script needs ELF builds of the same projects from ESP-IDF, Arduino and the ESP8266 SDK. Each
build goes in a folder with one subfolder per chip (`esp32`, `esp32s3`; `esp8266`), holding
`firmware.elf` and, for ESP-IDF, `bootloader.elf`, `bootloader.bin` and `partitions.bin`.

```bash
ESPTOOL=esptool Tools/oracle/make-references.sh <refs> <esp-idf builds> <arduino builds> <esp8266 builds>
```

```bash
ESPKIT_IMAGE_REFERENCES=<refs> swift test --filter ReferenceTests
```

The output has one file per case and a `cases.tsv` manifest (name, chip, ELF, esptool
arguments). ESPKit then rebuilds each case and compares the bytes. The references have been
checked with esptool 4.11 and 5.1.

### Security: espsecure

The script takes an ESP32-S3 application image to sign. It generates keys, digests, signatures
and ciphertexts for each scheme (Secure Boot v1, RSA-3072, ECDSA P-256 and P-384, XTS-AES-128
and 256).

```bash
ESPSECURE=espsecure Tools/oracle/make-secure-references.sh <refs> <image.bin>
```

```bash
ESPKIT_SECURE_REFERENCES=<refs> ESPKIT_ESPSECURE=espsecure swift test --filter ESPSecureTests
```

With `ESPKIT_ESPSECURE` set, the suite also signs images with ESPKit and has
`espsecure verify-signature` check them.

### eFuses: espefuse (read only)

Without a board, the script records `espefuse --virt` summaries for every chip: those are the
labels the table generator uses. With boards, add `<chip> <port>` pairs. It then also records
each board's summary and register dump, which the tests compare with ESPKit's decoding.

```bash
ESPEFUSE=espefuse Tools/oracle/make-efuse-references.sh <refs> esp32 /dev/cu.usbserial-0001 esp32s3 /dev/cu.usbmodem1101
```

```bash
ESPKIT_EFUSE_REFERENCES=<refs> swift test --filter ESPEfuseTests
```

espefuse only reads here: the script never burns.

### eFuse burning: espefuse --virt

The script replays the programming scenarios in espefuse's virtual mode, so no chip is touched.
Run it in an empty folder holding `key-ecdsa256.pem`, a Secure Boot v2 ECDSA P-256 key.

```bash
Tools/oracle/make-burn-references.sh
```

```bash
ESPKIT_BURN_REFERENCES=<folder> swift test --filter ESPEfuseTests
```

ESPKit plays the same scenarios on its virtual controller, and the final eFuse states must match
byte for byte, including the ESP32's 3/4 coding scheme.

## Hardware tests

The hardware suites are nested under one serialized `Boards` suite, so two tests never open the
same port at once. Each board is given by its port:

| Variable | Meaning |
|---|---|
| `ESPKIT_PORT_ESP32` | Port of an ESP32 board (through a USB-UART bridge such as the CH340 or CP2102) |
| `ESPKIT_PORT_S3` | Port of an ESP32-S3 board (USB-UART bridge or native USB-Serial-JTAG) |
| `ESPKIT_FIRMWARE_ESP32`, `ESPKIT_FIRMWARE_S3` | A build folder to flash on that board (see below) |
| `ESPKIT_BURN_ESP32` | Port of a **sacrificial** ESP32 for the eFuse burning suite |

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
```

Close every serial monitor first (PlatformIO, `screen`, the Arduino IDE): a port can only be open
once. The tests put each board in download mode through DTR and RTS, so the board must have the
usual auto-reset circuit, or USB-Serial-JTAG on the S3.

### What runs

With a port set:

- detection under the ROM, security information (S3), MAC address and flash identity;
- flash status registers, SFDP and memory reads;
- a differential reflash: only the changed sectors are sent;
- an encrypted write: refused until `ignoreEncryptionEfuses` is set, then the chip encrypts with
  its own key and the read-back must differ from the plaintext. On a fresh ESP32, it must match the
  zero-key model;
- the bundled stub loaded into RAM and run;
- with `ESPKIT_EFUSE_REFERENCES`, the board's eFuses decoded and compared with espefuse's summary.

These tests never burn an eFuse. They write only to a scratch area of the flash, from 0x300000
upward, and erase it at the end, so the application on the board survives.

### Flashing a real firmware

With `ESPKIT_FIRMWARE_<chip>` set too, the tests flash a real application with the stub at
460,800 baud, read it back, reset the board and wait for it to boot. This replaces the bootloader,
the partition table and the application on the board. The folder holds `bootloader.bin`, `partitions.bin` and `firmware.bin`, as a
PlatformIO build leaves them in `.pio/build/<env>`. The application must print
`ESPKit HIL OK <chip>` on its console, for example under ESP-IDF:

```c
printf("ESPKit HIL OK %s\n", CONFIG_IDF_TARGET);
```

```bash
ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_FIRMWARE_ESP32=…/.pio/build/esp32 swift test --filter HardwareTests
```

The test prints the connection, write and read times. The same build also serves the test that
starts the flash application from download mode.

### Burning eFuses: sacrificial board only

> Warning: eFuse burns cannot be undone. Use a board you are ready to lose, and never set
> `ESPKIT_BURN_ESP32` to the port of a board you need.

```bash
ESPKIT_BURN_ESP32=/dev/cu.usbserial-0001 swift test --filter EfuseBurnHardwareTests
```

The suite connects under the ROM at 115,200 baud, so the controller's timing is computed from an
exact APB clock. It checks the preview before each burn, then reads every block back after each
step. It only touches bits that no ESP-IDF feature uses, so the board keeps booting:

- **the next free bit of BLOCK3** (bits 192 to 255, no field there): one bit per run, so it can run
  64 times;
- **a custom MAC address** in BLOCK3: once;
- **a Secure Boot v1 key** in BLOCK2, then its read and write protection in BLOCK0: once. Secure
  Boot itself stays disabled (`ABS_DONE_0` is never burned).

The tests that can only run once report that they have nothing left to do on a board that has
already been through them. Hardware burning is implemented for the ESP32 with the NONE coding
scheme only; other chips refuse it.

## Reference data and generated code

Two parts of the sources are generated, and the differential tests check them.

The eFuse tables in `Sources/ESPEfuse/Generated` come from ESP-IDF's `esp_efuse_table.csv`
files. The labels recorded by `make-efuse-references.sh` only align names and categories with
espefuse:

```bash
python3 -I Tools/efuse-codegen/generate.py <esp-idf>/components/efuse <refs>/real <refs>/virt
```

The bundled flasher stub comes from an esp-flasher-stub release (the JSON files of its assets):

```bash
python3 -I Tools/generate-stubs.py v2.0.0 <folder of downloaded JSON files>
```

## Writing tests

- Use Swift Testing (`@Suite`, `@Test`, `#expect`), not XCTest.
- A test that needs a board, a tool or a reference folder is enabled by its environment variable
  (`.enabled(if:)`) and skipped otherwise. A test that needs a board also goes under the `Boards`
  suite.
- Compare with Espressif's tools through their outputs only: never copy or translate their code
  (GPL).
- Prefer the simulated chip to a board. Hardware tests confirm what the simulation cannot, such as
  timing, resets, real flash chips and eFuses.
