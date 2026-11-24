# Custom Transports

Talk to a chip over something other than a local serial port.

## Overview

`ESPDevice` only needs a ``Transport``: a byte channel that can also set two control lines and
change its baud rate. ``SerialPort`` is one; a TCP bridge, a USB library or a test double can be
another.

```swift
actor BridgeTransport: Transport {
    nonisolated let usbIdentity: USBIdentity? = nil

    func open() async throws { /* connect */ }
    func close() async { /* disconnect */ }
    func write(_ data: Data) async throws { /* send */ }
    func read(maxCount: Int, timeout: Duration) async throws -> Data { /* receive, or Data() on timeout */ }
    func discardInput() async throws { /* drop buffered bytes */ }
    func setBaudRate(_ rate: Int) async throws { /* forward, or ignore on a fixed-rate link */ }
    func setControlLines(dtr: Bool?, rts: Bool?) async throws { /* forward DTR/RTS */ }
}

let esp = try await ESPDevice.connect(BridgeTransport())
```

Keep these rules:

- ``Transport/read(maxCount:timeout:)`` returns as soon as bytes are available, and returns empty
  data — not an error — when the timeout expires.
- ``Transport/setControlLines(dtr:rts:)`` changes both lines at once when both are given;
  ``ResetSequence/unixTight(holdBootFor:)`` relies on it.
- Throw ``TransportError/deviceRemoved`` when the link goes away, so callers can tell an unplugged
  cable from a protocol error.
- If the link cannot toggle lines, set `ConnectOptions.entryReset` to ``EntryReset/none`` and put
  the chip in download mode another way.
