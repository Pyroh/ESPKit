# Serial Ports and Resets

Serial ports, port discovery and the reset sequences that put a chip into download mode.

## Overview

The ESPTransport module moves bytes. ``SerialPort`` is a POSIX serial port that accepts any baud rate
(IOSSIOSPEED on macOS, termios2 on Linux) and never blocks a Swift Concurrency thread.
``SerialPorts`` lists the ports present, with their USB identity. ``ResetSequence`` and
``EntryReset`` describe how DTR and RTS toggle the boot pins.

```swift
import ESPKit

for port in try SerialPorts.available(matching: PortFilter(vendorID: USBIdentity.espressifVendorID)) {
    print(port.path, port.usb?.product ?? "")
}
```

You rarely use these types directly: `ESPDevice.connect(port:options:)` opens the port and
performs the reset for you. It matters when the wiring is unusual (<doc:ResetSequences>) or when
the chip sits behind something other than a local serial port (<doc:CustomTransports>).

## Topics

### Essentials

- <doc:ResetSequences>
- <doc:CustomTransports>

### Ports

- ``SerialPort``
- ``SerialPorts``
- ``SerialPortInfo``
- ``PortFilter``
- ``USBIdentity``

### Resets

- ``EntryReset``
- ``ExitReset``
- ``ResetSequence``

### Custom links

- ``Transport``

### Errors

- ``TransportError``
