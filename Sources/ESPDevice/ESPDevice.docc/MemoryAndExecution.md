# Memory and Execution

Read registers and memory, run code from RAM, and start the application in flash.

## Overview

- ``ESPDevice/readRegister(_:)`` and ``ESPDevice/writeRegister(_:_:mask:delay:)`` read and write
  one 32-bit word (`read-mem`, `write-mem`).
- ``ESPDevice/readMemory(at:count:)`` reads a range word by word (`dump-mem`). Reading an
  unmapped address can hang or reset the chip.
- ``ESPDevice/macAddress()``, ``ESPDevice/securityInfo()`` and ``ESPDevice/chipID()`` (ESP8266
  only) read the chip's identity.

### Code in RAM

``ESPDevice/loadRAMAndRun(_:)`` copies a `FirmwareImage` (from ESPImage) into RAM and jumps to its
entry point, without touching the flash (`load-ram`). The session ends: the chip now runs your
code, and the actor moves to ``ESPDevice/State/closed`` without a reset. Segments mapped from
flash are refused.

### Starting the application

``ESPDevice/runFlashApplication()`` leaves the bootloader and starts the application in flash
(`run`). It resets the chip with the boot pin released, like ``ESPDevice/disconnect(_:)`` with
`ExitReset.hard`. The ROM's "run user code" command is not used: on the ESP32 and ESP32-S3 it
only calls an empty ROM hook and the application does not start.
