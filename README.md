# ESPKit

A Swift SDK for talking to the serial bootloader of Espressif chips (ESP8266, ESP32 and the ESP32-x family): detection, flashing, images, Secure Boot, flash encryption and eFuses. An independent reimplementation of what esptool, espefuse and espsecure can do, without a CLI.

- **Platforms:** macOS 15+ and Linux.
- **Language:** Swift 6.2 or later (swift-crypto 5.1), strict concurrency. `ESPDevice` is an `actor`; long-running operations are `AsyncSequence`s.
- **Products:** `ESPKit` (everything), plus `ESPImage` and `ESPSecure` (each with `ESPTargets`) for tools that build or sign images without a chip.
- **License:** MIT OR Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE`).

The public API specification is the reference; it lives in the research folder (`ESPKit-API.md`).

## Disclaimer

ESPKit is provided "as is", without warranty of any kind, express or implied, as its licences
(MIT and Apache-2.0) state. It writes flash memory and can burn eFuses, which cannot be undone: a
wrong write, an interrupted transfer or a wrong eFuse can leave a board unusable or permanently
locked. You use it at your own risk; the authors and contributors are not liable for damaged,
bricked or locked hardware, lost data, or any other damage.

Bug reports are welcome, though: open an issue at <https://github.com/Pyroh/ESPKit/issues> with the
chip, the board and USB adapter, the ESPKit commit and, when the problem involves the chip, a trace
(`ConnectOptions.trace`).

ESPKit is an independent project, not affiliated with, endorsed or supported by Espressif Systems.
Product names are trademarks of their respective owners.

## Example

```swift
import ESPKit

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")   // v2 stub, 460,800 baud
let regions = [
    FlashRegion(address: esp.chip.bootloaderOffset, data: try Data(contentsOf: bootloader)),
    FlashRegion(address: 0x8000, data: try Data(contentsOf: partitions)),
    FlashRegion(address: 0x10000, data: try Data(contentsOf: firmware)),
]
for try await event in esp.writeFlash(regions) {
    if case .progress(let p) = event { print(p.stage, Int(p.fractionCompleted * 100), "%") }
}
await esp.disconnect(.hard)
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
