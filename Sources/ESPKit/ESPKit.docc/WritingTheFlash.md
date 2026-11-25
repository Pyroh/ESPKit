# Writing the Flash

Write, read back, verify and erase the SPI flash, including differential and encrypted writes.

## Overview

``ESPDevice/writeFlash(_:options:)-(FlashRegions,_)`` writes a build, given as ``FlashRegions``:
its bootloader, partition table and application, without their addresses.
``ESPDevice/writeFlash(_:options:)-([FlashRegion],_)`` writes any list of ``FlashRegion`` values,
each at the address you give. Both return an ``ESPOperation`` whose result is a
``WriteFlashReport``. With the stub, data travels zlib-compressed in 16 KiB blocks, and each region
is checked afterwards against the MD5 the chip computes.

```swift
let build = FlashRegions(bootloader: bootloader, partitionTable: partitions, application: application)
for try await event in esp.writeFlash(build) {
    switch event {
    case .progress(let progress): print(progress.stage, Int(progress.fractionCompleted * 100), "%")
    case .finished(let report): print(report.regions.map(\.bytesSent))
    }
}
```

Before anything is sent, ESPKit rejects empty, overlapping or out-of-flash regions, an image built
for another chip, and writes below 0x8000 while Secure Boot is enabled; ``WriteFlashOptions/force``
lifts the last two.

### Where a build goes

Only the bootloader's address is fixed by the chip. The others come from the build, and
``FlashRegions`` resolves them for the connected chip when the operation runs:

| File | Address |
|---|---|
| Bootloader | ``ChipFamily/bootloaderOffset``: the ROM looks for it at 0x1000 on the ESP32 and ESP32-S2, 0x2000 on the ESP32-C5, H4, P4 and S31, 0x0 on the others |
| Partition table | ``FlashRegions/partitionTableOffset``: 0x8000 unless the build moved it with `CONFIG_PARTITION_TABLE_OFFSET`, as large or secure bootloaders need |
| Application | The partition the bootloader boots, read from the table: `factory`, or `ota_0` when there is none |
| `otadata` | Erased when the table has it, so that an earlier OTA update does not keep another partition selected. `idf.py flash` does the same. |

Before anything is sent, ESPKit rejects a partition table it cannot read (bad magic, MD5
mismatch), a table without a `factory` or `ota_0` partition, an application larger than its
partition, and a bootloader that runs into the partition table: ``PartitionTableError``.

``FlashRegions/resolved(for:)`` returns the same regions, to merge the build into one file with
``MergedImage`` or to check it with ``ESPDevice/verifyFlash(_:)``. Write explicit regions for
anything else: a data partition image (NVS, SPIFFS, LittleFS), a merged image at 0x0, or an
ESP8266 Arduino build, which has no partition table.

### Bootloader header

The region at `ChipFamily.bootloaderOffset` is the second-stage bootloader. Its header carries
the flash mode, frequency and size; ``WriteFlashOptions/headerOverrides`` rewrites them as
esptool's `--flash-mode`, `--flash-freq` and `--flash-size` do, and recomputes the image's
SHA-256. `.detect` uses the size read from the flash's JEDEC ID.

### Writing less

- ``WriteFlashOptions/skipIfUnchanged`` compares MD5 digests first and skips regions already in
  place (`--skip-flashed`).
- ``WriteFlashOptions/previousContents`` gives what the flash is assumed to hold. Only the 4 KiB
  sectors that differ are sent (`--diff-with`). Unless ``WriteFlashOptions/trustPreviousContents``,
  ESPKit first asks the chip for the MD5 of the old content and writes the whole region if it
  does not match. The final MD5 check covers the whole region either way.

### Encrypted writes

Set `FlashRegion.encrypt` to let the chip encrypt a region with its own flash encryption key
while writing (`--encrypt-files`). Such regions are sent uncompressed, padded with 0xFF to
16 bytes (32 on the ESP32), and are not verified: the flash holds ciphertext. ESPKit refuses them
unless flash encryption is enabled in the eFuses, or ``WriteFlashOptions/ignoreEncryptionEfuses``
is set. The ESP32 needs the stub for this; to produce ciphertext offline instead, use
``FlashEncryption`` from ESPSecure and write the result in plaintext.

### Reading, verifying, erasing

- ``ESPDevice/readFlash(at:count:)`` reads a range; with the stub, the read is checked against the
  MD5 the chip sends at the end.
- ``ESPDevice/verifyFlash(_:)`` compares regions with the flash and lists the first differing bytes.
- ``ESPDevice/flashMD5(at:count:)`` asks the chip for a digest without transferring data.
- ``ESPDevice/eraseFlash(force:)`` erases everything; ``ESPDevice/eraseRegion(at:count:force:)``
  erases whole 4 KiB sectors. Both need the stub and refuse when Secure Boot or flash encryption
  is enabled, unless `force`.

### Flash registers

``ESPDevice/readFlashStatus(byteCount:)``, ``ESPDevice/writeFlashStatus(_:byteCount:nonVolatile:)``
and ``ESPDevice/readSFDP(at:count:)`` reach the flash chip itself. A wrong status value can
write-protect the flash or disable its quad mode: write only what you read and changed.
``ESPDevice/spiFlashCommand(_:data:readBits:)`` sends any other SPI command.
