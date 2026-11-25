# Connecting to a Chip

Open a session, choose between the ROM and the stub, and close it cleanly.

## Overview

``ESPDevice/connect(port:options:)`` does what `esptool` does before any command:

1. opens the port at the initial baud rate (115,200);
2. plays the entry reset (`ConnectOptions.entryReset`) so the chip boots into its ROM bootloader;
3. sends SYNC until the ROM answers, up to ``ConnectOptions/connectAttempts`` times;
4. detects the chip from GET_SECURITY_INFO or, on older ROMs, from a magic register value;
5. loads the stub (``ConnectOptions/stub``) and switches to ``ConnectOptions/baudRate``.

```swift
var options = ConnectOptions()
options.expectedChip = .esp32s3          // fail early on the wrong board
options.baudRate = 921_600
let esp = try await ESPDevice.connect(port: "/dev/cu.usbmodem1101", options: options)
```

When you do not know the port, ``ESPDevice/connectFirstAvailable(matching:options:)`` tries every
port that matches a filter and returns the first chip that answers.

### ROM or stub

The ROM bootloader is always there, but it is slow and limited: no compressed reads, small blocks,
and on the ESP8266, ESP32 and ESP32-C2 a baud rate change that computes the divider wrongly. The
stub is a small program ESPKit loads into RAM; it speaks the same protocol, faster, with more
commands (full erase, region erase, fast reads). ``StubPolicy/load`` is the default.

Use ``StubPolicy/romOnly`` when the stub cannot run: Secure Download Mode, an ESP32-C3 with
Secure Boot enabled, or when you want to test the ROM itself. ``StubPolicy/custom(_:)`` loads
your own ``StubImage``, built from raw segments or from an esp-flasher-stub JSON release file.

``ESPDevice/state`` tells who answers: ``ESPDevice/State/rom``,
``ESPDevice/State/stub(_:)``, ``ESPDevice/State/secureDownloadMode`` or
``ESPDevice/State/closed``.

### Secure Download Mode

A chip with Secure Download Mode enabled only accepts a few ROM commands. ESPKit detects it at
connection: ``ESPDevice/securityInfo()``, ``ESPDevice/writeFlash(_:options:)-([FlashRegion],_)`` and
``ESPDevice/eraseRegion(at:count:force:)`` stay available; every other operation throws
``UsageError/unavailableInSecureDownloadMode(operation:)`` without sending anything.

### Ending the session

``ESPDevice/disconnect(_:)`` applies an ``ExitReset`` and closes the port. `ExitReset.hard`
restarts the chip into its application; `ExitReset.stayInBootloader` leaves it in the ROM.
After `disconnect`, every call throws ``ConnectionError/disconnected``.

### Tracing

Set ``ConnectOptions/trace`` to receive every reset step, command and response as a
``TraceEvent``, the equivalent of `esptool --trace`:

```swift
let (events, continuation) = AsyncStream.makeStream(of: TraceEvent.self)
var options = ConnectOptions()
options.trace = continuation
Task { for await event in events { print(event) } }
let esp = try await ESPDevice.connect(port: path, options: options)
```
