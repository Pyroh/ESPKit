# Writing the Flash

Write, read back, verify and erase the SPI flash, including differential and encrypted writes.

## Overview

``ESPDevice/writeFlash(_:options:)`` takes the regions to write and returns an ``ESPOperation``
whose result is a ``WriteFlashReport``. With the stub, data travels zlib-compressed in 16 KiB
blocks, and each region is checked afterwards against the MD5 the chip computes.

```swift
let regions = [
    FlashRegion(address: esp.chip.bootloaderOffset, data: bootloader),
    FlashRegion(address: 0x8000, data: partitions),
    FlashRegion(address: 0x10000, data: application),
]
for try await event in esp.writeFlash(regions) {
    switch event {
    case .progress(let progress): print(progress.stage, Int(progress.fractionCompleted * 100), "%")
    case .finished(let report): print(report.regions.map(\.bytesSent))
    }
}
```

Before anything is sent, ESPKit rejects empty, overlapping or out-of-flash regions, an image built
for another chip, and writes below 0x8000 while Secure Boot is enabled; ``WriteFlashOptions/force``
lifts the last two.

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
`FlashEncryption` from ESPSecure and write the result in plaintext.

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
