# Merging and Inspecting Images

Combine bootloader, partition table and application into one file, and read images back.

## Overview

``MergedImage`` produces the three formats of `esptool merge-bin`:

```swift
let regions = [
    FlashRegion(address: 0x0, data: bootloader),
    FlashRegion(address: 0x8000, data: partitions),
    FlashRegion(address: 0x10000, data: application),
]
let raw = try MergedImage.raw(regions, chip: .esp32s3, padTo: .mb8)
let hex = try MergedImage.intelHex(regions, chip: .esp32s3)
let uf2 = try MergedImage.uf2(regions, chip: .esp32s3)
```

- ``MergedImage/raw(_:chip:targetOffset:padTo:headerOverrides:)`` fills gaps with 0xFF; with a
  target offset, the file starts there instead of at 0.
- ``MergedImage/intelHex(_:chip:headerOverrides:)`` writes 16-byte records and leaves gaps out.
- ``MergedImage/uf2(_:chip:chunkSize:includeMD5:headerOverrides:)`` writes 512-byte UF2 blocks
  with the chip's family ID, for drag-and-drop flashing.

All three can patch the bootloader header on the way, like `writeFlash` does.
``IntelHex/parse(_:)`` reads an Intel HEX file back into regions.

### Inspecting

``AnyFirmwareImage/init(parsing:chip:)`` reads a binary whose format is unknown, the equivalent of
`esptool image-info`. ``FirmwareImage/validate()`` then checks the checksum, the SHA-256, segment
overlaps and the MMU alignment of flash segments; an empty ``ImageValidation/issues`` list means
the image is consistent.

```swift
switch try AnyFirmwareImage(parsing: bin) {
case .esp32Family(let image):
    print(image.chip.map(String.init(describing:)) ?? "?", image.appDescription?.version ?? "")
    print(image.validate().issues)
case .esp8266(let image):
    print(image.format, image.validate().isValid)
}
```
