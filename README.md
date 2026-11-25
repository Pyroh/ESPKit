# ESPKit

A Swift SDK for talking to the serial bootloader of Espressif chips (ESP8266, ESP32 and the ESP32-x family): detection, flashing, images, Secure Boot, flash encryption and eFuses. An independent reimplementation of what esptool, espefuse and espsecure can do, without a CLI.

- **Platforms:** macOS 15+ and Linux.
- **Language:** Swift 6.2 or later (swift-crypto 5.1), strict concurrency. `ESPDevice` is an `actor`; long-running operations are `AsyncSequence`s.
- **Products:** `ESPKit` (everything), plus `ESPImage` and `ESPSecure` (each with `ESPTargets`) for tools that build or sign images without a chip.
- **License:** MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`).

The public API specification is the reference; it lives in the research folder (`ESPKit-API.md`).

## Disclaimer

> [!CAUTION]
> ESPKit is provided "as is", without warranty of any kind, express or implied, as its licences
> (MIT and Apache-2.0) state. It writes flash memory and can burn eFuses, which cannot be undone: a
> wrong write, an interrupted transfer or a wrong eFuse can leave a board unusable or permanently
> locked. You use it at your own risk; the authors and contributors are not liable for damaged,
> bricked or locked hardware, lost data, or any other damage.

Bug reports are welcome, though: open an issue at <https://github.com/Pyroh/ESPKit/issues> with the
chip, the board and USB adapter, the ESPKit commit and, when the problem involves the chip, a trace
(`ConnectOptions.trace`).

ESPKit is an independent project, not affiliated with, endorsed or supported by Espressif Systems.
Product names are trademarks of their respective owners.

## What it does

### Find a board and connect

```swift
import ESPKit

// Serial ports, with their USB identity (IOKit on macOS, sysfs on Linux).
for port in try SerialPorts.available() {
    print(port.path, port.usb?.product ?? "")
}

// Resets the chip into its ROM bootloader, identifies it, loads the flasher stub
// and switches to 460,800 baud.
let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")
print(esp.chip.displayName)                     // ESP32-S3
print(try await esp.macAddress())               // 24:0A:C4:12:34:56
print(try await esp.flashInfo().detectedSize!)  // 8MB
```

### Long operations

Writing, reading, verifying or erasing the flash takes from a few seconds to several minutes over a
serial link. So `writeFlash`, `readFlash`, `verifyFlash`, `eraseFlash` and `readMemory` do not
wait until the work is done. Each returns an `ESPOperation`: a description of the work, which you
run by consuming it as an `AsyncSequence`.

- **Cold:** nothing reaches the chip until you iterate the operation or await its `.value`.
  Iterating it again runs it again.
- **Events:** it yields `.progress` events (stage, region, bytes done), then a single `.finished`
  carrying the result: a write report, the bytes read, the verification results.
- **Never slowed down:** if the consumer (a UI, say) is slower than the chip, it only gets the
  latest progress; the final event is never dropped.
- **Cancellable:** cancelling the task, or leaving the loop, stops the operation at the next block.
  The session stays open, ready for the next operation.
- **In order:** operations on one `ESPDevice` run one after the other, even when several tasks
  start them at once.

```swift
// The result only.
let partitionTable = try await esp.readFlash(at: 0x8000, count: 0xC00).value

// Progress only, for an operation without a result.
for try await progress in esp.eraseFlash().progress {
    print(progress.stage)
}

// Cancellation: cancel the task that runs the operation.
let backup = Task { try await esp.readFlash(at: 0, count: nil).value }
backup.cancel()     // `try await backup.value` then throws CancellationError
```

### Flash a firmware

Writes are compressed and checked by MD5. The loop follows the progress of the write, then gets
its report.

```swift
let regions = [
    FlashRegion(address: esp.chip.bootloaderOffset, data: bootloader),
    FlashRegion(address: 0x8000, data: partitions),
    FlashRegion(address: 0x10000, data: application),
]

for try await event in esp.writeFlash(regions) {
    switch event {
    case .progress(let progress):
        print(progress.stage, Int(progress.fractionCompleted * 100), "%")
    case .finished(let report):
        print("\(report.regions.count) regions written and checked by MD5")
    }
}

// Next build: give what is already on the chip, and only the 4 KiB sectors
// that changed are sent.
var options = WriteFlashOptions()
options.previousContents = regions
let report = try await esp.writeFlash([FlashRegion(address: 0x10000, data: newApplication)], options: options).value
print(report.regions[0].bytesSent, "bytes sent")
```

### Read, verify, erase

```swift
let backup = try await esp.readFlash(at: 0, count: nil).value   // nil: the whole flash

// Compares MD5 digests; on a mismatch, reads back and reports the first differences.
for case .mismatch(let address, let differences) in try await esp.verifyFlash(regions).value {
    print("0x\(String(address, radix: 16)): \(differences.count) bytes differ")
}

try await esp.eraseRegion(at: 0x9000, count: 0x6000)   // the NVS partition
await esp.disconnect(.hard)                             // reset into the application
```

### Build and merge images, without a chip

`ESPImage` turns an ELF file into a flashable image, byte-identical to esptool's, and merges
several images into a single file.

```swift
let elf = try ELFFile(parsing: Data(contentsOf: elfURL))
var options = ImageOptions()
options.flashMode = .dio
options.flashSize = .mb4
let app = try ImageBuilder.makeImage(from: elf, chip: .esp32s3, options: options).serialized()

// One file for a web flasher or an OTA server, or a UF2 for drag-and-drop.
let regions = [
    FlashRegion(address: 0x0, data: bootloader),
    FlashRegion(address: 0x8000, data: partitions),
    FlashRegion(address: 0x10000, data: app),
]
try MergedImage.raw(regions, chip: .esp32s3).write(to: mergedURL)
try MergedImage.uf2(regions, chip: .esp32s3).write(to: uf2URL)

// Reading an image: header, segments, app description, validation.
if case .esp32Family(let image) = try AnyFirmwareImage(parsing: app) {
    print(image.appDescription?.projectName ?? "", image.appDescription?.version ?? "")
    print(image.validate().isValid ? "valid" : image.validate().issues)
}
```

### Sign and encrypt, without a chip

`ESPSecure` does what espsecure does: Secure Boot v2 signatures (which espsecure verifies),
Secure Boot v1 on the ESP32, and flash encryption done in advance.

```swift
// Secure Boot v2: RSA-3072, ECDSA P-256 or P-384 keys, in PEM like espsecure's.
let key = try SecureBootV2.SigningKey.generate(.ecdsa256)
try key.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)

let signed = try SecureBootV2.sign(app, with: [key])         // signature block appended
try SecureBootV2.verify(signed, publicKey: key.publicKey)
print(key.publicKey.digest.map { String(format: "%02x", $0) }.joined())   // goes into an eFuse key block

// Flash encryption, offline: the same ciphertext the chip would write.
let flashKey = FlashEncryption.generateKey(for: .xtsAES128)
let encrypted = try FlashEncryption.encrypt(signed, at: 0x10000, key: flashKey, scheme: .xtsAES128)
```

### Read and burn eFuses

eFuses are decoded with tables generated from ESP-IDF for 12 chips. Burns go through a plan that
you can preview and rehearse on a virtual chip. On a real chip, burning is supported on the ESP32
only for now.

```swift
let efuses = try await EfuseController(device: esp)
for field in await efuses.fields() where field.category == "security" {
    print(field.name, field.displayValue)
}
let summary = await efuses.summaryJSON()    // byte-identical to `espefuse summary --format json`

// Burning is irreversible: build a plan, rehearse it on a virtual chip, read the preview.
var plan = EfuseBurnPlan()
plan.writeKeyDigest(key.publicKey, to: .key0, purpose: .secureBootDigest0)

let rehearsal = EfuseController(virtual: .esp32s3)
for change in try await rehearsal.preview(plan) {
    print(change)          // BLOCK4 word 0: 00000000 → a3b0cd8e
}
let report = try await rehearsal.burn(plan, confirm: .irreversible)
print(report.steps.count, "steps, read back after each one")
```

## Documentation

Every public symbol is documented in a single DocC catalog, `Sources/ESPKit/ESPKit.docc`, with one
entry point: the API grouped by topic (talking to a chip, serial ports, chips and flash settings,
images, Secure Boot and flash encryption, eFuses) and the guides (connecting, writing the flash,
building images, signing, reading and burning eFuses, the correspondence with esptool). To build it,
with no plugin:

```bash
Tools/build-docs.sh
```

The archive lands in `.build/documentation/ESPKit.doccarchive`. Double-click it to read it in Xcode,
or open it in Dash, which indexes it as a docset (copy it out of `.build` first: the next build
replaces it). Preview it live with
`xcrun docc preview Sources/ESPKit/ESPKit.docc --additional-symbol-graph-dir .build/documentation/graphs`.
`WARNINGS_AS_ERRORS=1` makes any broken link fail the build, as in CI.

## Tests

`swift test` runs everything that needs neither a chip nor Espressif's tools. The differential
tests against esptool, espsecure and espefuse, the hardware tests and the (irreversible) eFuse
burning tests are described in [TESTING.md](TESTING.md).

## Contribution rules

- Code is written from the specification and public documentation, never by translating esptool's Python (GPL).
- Every file carries the `// SPDX-License-Identifier: MIT OR Apache-2.0` header.
- Accepted dependencies: `swift-crypto` (5.1.x), system libz (the `zlib1g-dev` package on Linux). Nothing under GPL or LGPL.
