# Firmware Images

Firmware images without a chip: ELF to image, image inspection, merging into raw, Intel HEX and UF2 files.

## Overview

These types come from the ESPImage module, which is pure: it reads and writes bytes and never
talks to a chip. Besides `import ESPKit`, it comes as a product of its own, with ESPTargets, for
tools that build images without a chip. Its output is
byte-identical to esptool 4.11 and 5.1 on ESP-IDF and Arduino builds.

```swift
import ESPImage
import ESPTargets

let elf = try ELFFile(parsing: try Data(contentsOf: elfURL))
var options = ImageOptions()
options.flashMode = .dio
options.flashSize = .mb4
let image = try ImageBuilder.makeImage(from: elf, chip: .esp32s3, options: options)
try image.serialized().write(to: binURL)
```

## Topics

### Essentials

- <doc:BuildingImages>
- <doc:MergingAndInspecting>

### ELF files

- ``ELFFile``

### Building

- ``ImageBuilder``
- ``ImageOptions``
- ``ESP8266ImageVersion``

### Images

- ``FirmwareImage``
- ``ESP8266Image``
- ``AnyFirmwareImage``
- ``AppDescription``
- ``BootloaderDescription``
- ``SPIPinDrive``
- ``MemoryRegion``
- ``ImageValidation``

### Builds

- ``FlashRegions``
- ``PartitionTableError``

### Merging

- ``MergedImage``
- ``IntelHex``

### Errors

- ``ImageError``
