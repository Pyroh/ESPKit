# ``ESPKit``

A Swift SDK for Espressif chips: flash, images, Secure Boot, flash encryption and eFuses, without esptool.

## Overview

ESPKit talks to the serial bootloader of the ESP8266, the ESP32 and the ESP32-x family. It is an
independent reimplementation of what esptool, espefuse and espsecure do, as a library: no command
line, strict Swift concurrency, macOS 15 and Linux.

`import ESPKit` brings in every module; this documentation covers them all, by topic:

| Module | What it does |
|---|---|
| ESPTargets | Chip families, revisions, MAC addresses, flash settings and regions |
| ESPTransport | Serial ports, port discovery, reset sequences |
| ESPDevice | The ``ESPDevice`` actor: connect, flash, read, verify, erase, registers, RAM |
| ESPImage | ELF to image, image inspection, raw / Intel HEX / UF2 merging |
| ESPSecure | Secure Boot v1 and v2 signatures, offline flash encryption |
| ESPEfuse | Reading, decoding and burning eFuses |

The package has three products: `ESPKit` for everything, and `ESPImage` and `ESPSecure` (each with
ESPTargets) for tools that build or sign images without a chip and should not link the serial code.

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

> Important: ESPKit is provided "as is", without warranty of any kind, express or implied, as its licences (MIT and Apache-2.0) state. It writes flash memory and can burn eFuses, which cannot be undone: a wrong write, an interrupted transfer or a wrong eFuse can leave a board unusable or permanently locked. You use it at your own risk; the authors and contributors are not liable for damaged, bricked or locked hardware, lost data, or any other damage.
> ESPKit is an independent project, not affiliated with, endorsed or supported by Espressif Systems.
> Bug reports are welcome: <https://github.com/Pyroh/ESPKit/issues>.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:EsptoolCorrespondence>
- <doc:CompatibilityAndTesting>

### API by topic

- <doc:TalkingToAChip>
- <doc:SerialPortsAndResets>
- <doc:ChipsAndFlashSettings>
- <doc:FirmwareImages>
- <doc:SecureBootAndEncryption>
- <doc:Efuses>
