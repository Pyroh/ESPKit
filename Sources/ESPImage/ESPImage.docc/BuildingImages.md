# Building Images

Turn an ELF file into a flashable image, like `esptool elf2image`.

## Overview

``ImageBuilder/makeImage(from:chip:options:)`` lays out the ELF's loadable sections as image
segments:

- segments mapped from flash (IROM, DROM) are placed so that their file offset matches their
  address modulo the MMU page, with RAM segments or padding filling the gaps;
- the ESP-IDF app description comes first among the flash segments, and receives the ELF's
  SHA-256 (or set ``ImageOptions/elfSHA256Offset`` explicitly);
- the header carries the flash settings and the chip revision range; a SHA-256 of the image
  follows the checksum unless ``ImageOptions/appendSHA256`` is false.

```swift
let elf = try ELFFile(parsing: elfData)
var options = ImageOptions()
options.flashMode = .qio
options.flashFrequency = .mhz80
options.flashSize = .mb8
options.minRevision = ChipRevision(major: 0, minor: 0)
let image = try ImageBuilder.makeImage(from: elf, chip: .esp32s3, options: options)
let bin = try image.serialized()
```

### Options worth knowing

- ``ImageOptions/useSegments`` builds from the ELF's program headers instead of its sections
  (`--use-segments`).
- ``ImageOptions/securePadding`` leaves room for a Secure Boot signature, so that a v2 signature
  sector lands on an MMU page boundary.
- ``ImageOptions/padToMultipleOf`` pads the file with 0xFF (`--pad-to-size`).
- ``ImageOptions/ramOnlyHeader`` announces only the RAM segments in the header, for images the
  ROM loads directly (`--ram-only-header`). The flash segments follow the checksum in
  ``FirmwareImage/hiddenSegments``.

### ESP8266

``ImageBuilder/makeESP8266Image(from:version:options:)`` builds the two-file v1 layout (header
and RAM segments, then raw IROM at its flash offset) or the single-file v2 layout used by OTA
builds. Each file comes with the suffix esptool gives it.

### Chips

ESPImage knows the memory maps of the ESP8266, ESP32, S2, S3, C2, C3, C5, C6, C61, H2 and P4.
Other chips throw ``ImageError/unsupportedChip(_:)`` until their maps can be verified.
