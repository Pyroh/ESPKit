# Reset Sequences

How ESPKit puts a chip into download mode, and how to describe your own wiring.

## Overview

An Espressif chip enters its ROM bootloader when it comes out of reset with its boot pin
(GPIO0 on the ESP32, GPIO9 on most RISC-V chips) held low. Development boards wire two serial
control lines to do that from the host: through two transistors, DTR drives the boot pin and RTS
drives EN (reset). An asserted line pulls its pin low.

``EntryReset/automatic`` picks the right sequence:

- If the port reports Espressif's built-in USB-Serial-JTAG peripheral (USB ID 303A:1001), it plays
  ``ResetSequence/usbSerialJTAG``: the lines are virtual and the sequence differs.
- Otherwise it tries ``ResetSequence/unixTight(holdBootFor:)``, which changes both lines in a
  single system call so the chip never sees a spurious intermediate state, then
  ``ResetSequence/classic(holdBootFor:)``, which works with every driver.

At the end of a session, ``ExitReset`` says what to do: ``ExitReset/hard`` pulses EN so the
application starts; ``ExitReset/stayInBootloader`` leaves the chip where it is.

### Custom sequences

Boards with other wiring (an inverted transistor, a single line, a relay) take a custom sequence,
the equivalent of esptool's `--before custom`:

```swift
var options = ConnectOptions()
options.entryReset = .custom([
    .lines(dtr: false, rts: true),       // EN low: held in reset
    .wait(.milliseconds(100)),
    .lines(dtr: true, rts: false),       // boot pin low, EN released: download mode
    .wait(.milliseconds(50)),
    .dtr(false),
])
let esp = try await ESPDevice.connect(port: "/dev/cu.usbserial-0001", options: options)
```

If nothing can drive the pins, put the chip in download mode by hand (hold BOOT, press RESET) and
use ``EntryReset/none``.

### Two cables on one board

Some boards expose both a USB-to-serial bridge and the chip's native USB. Use one at a time:
the auto-reset circuit of the bridge and the USB-Serial-JTAG reset can fight each other.
