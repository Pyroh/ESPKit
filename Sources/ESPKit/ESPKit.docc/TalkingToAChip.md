# Talking to a Chip

A session with a chip in download mode: detection, flashing, reading, registers, memory and RAM code.

## Overview

``ESPDevice`` is an actor. ``ESPDevice/connect(port:options:)`` resets the chip into its ROM
bootloader, syncs, detects the family, loads the bundled flasher stub (esp-flasher-stub 2.0.0)
and raises the baud rate. Every operation then goes through the actor, so two exchanges never
interleave even when several tasks share the session.

```swift
import ESPKit

let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001")
print(esp.chip, try await esp.macAddress())

let build = FlashRegions(bootloader: bootloader, partitionTable: partitions, application: application)
let report = try await esp.writeFlash(build).value
await esp.disconnect(.hard)
```

Long operations — writing, reading, verifying, erasing — return an ``ESPOperation``: an
`AsyncSequence` of progress events that ends with the result, and that you can cancel like any
task.

## Topics

### Essentials

- <doc:ConnectingToAChip>
- <doc:WritingTheFlash>
- <doc:LongRunningOperations>

### Sessions

- ``ESPDevice``
- ``ConnectOptions``
- ``StubPolicy``
- ``StubImage``
- ``VDDSDIOOverride``

### Flash

- ``WriteFlashOptions``
- ``WriteFlashReport``
- ``VerifyResult``
- ``ByteDifference``
- ``FlashInfo``

### Operations

- ``ESPOperation``

### Memory and execution

- <doc:MemoryAndExecution>

### Security state

- ``SecurityInfo``

### Tracing

- ``TraceEvent``

### Errors

- <doc:HandlingErrors>
- ``ConnectionError``
- ``ProtocolError``
- ``DeviceErrorCode``
- ``UsageError``
- ``FlashError``
- ``StubError``
