# ESPKit

@Metadata {
    @TechnologyRoot
}

A Swift SDK for Espressif chips: flash, images, Secure Boot, flash encryption and eFuses, without esptool.

## Overview

ESPKit talks to the serial bootloader of the ESP8266, the ESP32 and the ESP32-x family. It is an
independent reimplementation of what esptool, espefuse and espsecure do, as a library: no command
line, strict Swift concurrency, macOS 15 and Linux.

`import ESPKit` brings in every module:

| Module | What it does |
|---|---|
| ESPTargets | Chip families, revisions, MAC addresses, flash settings and regions |
| ESPTransport | Serial ports, port discovery, reset sequences |
| ESPDevice | The `ESPDevice` actor: connect, flash, read, verify, erase, registers, RAM |
| ESPImage | ELF to image, image inspection, raw / Intel HEX / UF2 merging |
| ESPSecure | Secure Boot v1 and v2 signatures, offline flash encryption |
| ESPEfuse | Reading, decoding and burning eFuses |

Each module also works on its own: an app that only builds images imports ESPImage and never
links the serial code. Each module's documentation lists its types and guides.

```swift
import ESPKit

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")
let report = try await esp.writeFlash([
    FlashRegion(address: esp.chip.bootloaderOffset, data: bootloader),
    FlashRegion(address: 0x8000, data: partitions),
    FlashRegion(address: 0x10000, data: application),
]).value
await esp.disconnect(.hard)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:EsptoolCorrespondence>
- <doc:CompatibilityAndTesting>
