# Getting Started

Add ESPKit to a package, connect to a board and flash a build.

## Overview

### Add the package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Pyroh/ESPKit.git", branch: "main"),
],
targets: [
    .executableTarget(name: "Flasher", dependencies: ["ESPKit"]),
]
```

ESPKit needs Swift 6.2 and macOS 15, or Linux with the zlib development package
(`zlib1g-dev` on Debian and Ubuntu). Its only dependency is swift-crypto.

### Find the board

```swift
import ESPKit

for port in try SerialPorts.available() {
    print(port.path, port.usb.map { String(format: "%04X:%04X", $0.vendorID, $0.productID) } ?? "")
}
```

On macOS, boards show up as `/dev/cu.usbserial-*` (USB-to-serial bridge) or
`/dev/cu.usbmodem*` (native USB). On Linux, `/dev/ttyUSB*` or `/dev/ttyACM*`; your user needs
access to them (the `dialout` group on most distributions).

### Connect

```swift
let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")
print(esp.chip, try await esp.macAddress(), try await esp.flashInfo())
```

`connect` resets the chip into its bootloader, detects it, loads the flasher stub and raises the
baud rate to 460,800. ``ConnectOptions`` changes any of that.

### Flash a build

An ESP-IDF or PlatformIO build produces three binaries: the bootloader, the partition table and the
application. ``FlashRegions`` holds them; ESPKit works out where each one goes on the connected
chip.

```swift
let folder = URL(fileURLWithPath: ".pio/build/esp32s3")
let build = FlashRegions(
    bootloader: try Data(contentsOf: folder.appendingPathComponent("bootloader.bin")),
    partitionTable: try Data(contentsOf: folder.appendingPathComponent("partitions.bin")),
    application: try Data(contentsOf: folder.appendingPathComponent("firmware.bin")))
for try await event in esp.writeFlash(build) {
    if case .progress(let progress) = event {
        print(progress.stage, Int(progress.fractionCompleted * 100), "%")
    }
}
await esp.disconnect(.hard)          // restart into the new application
```

### Next steps

- Build images from an ELF instead of using the build's binaries: ``ImageBuilder`` in ESPImage.
- Sign them for Secure Boot: ``SecureBootV2`` in ESPSecure.
- Read the chip's security state: ``EfuseController`` in ESPEfuse.
