# Handling Errors

What each error type means and what to do about it.

## Overview

ESPKit functions use untyped `throws`, with one error type per domain. All conform to
`ESPKitError` (from ESPTargets) and give an English `description`; each function's documentation
lists the types it can throw.

| Type | Raised when | Typical fix |
|---|---|---|
| `TransportError` | the port cannot be opened, is busy, or went away | close the other program, check the cable |
| ``ConnectionError`` | no answer to SYNC, wrong or unknown chip, closed session | check the boot mode and the port |
| ``ProtocolError`` | a timeout, an inconsistent response, or a refusal by the chip (``DeviceErrorCode``) | retry; lower the baud rate |
| ``UsageError`` | a request the chip or the session cannot honour, or a safeguard | change the arguments, or use `force` |
| ``FlashError`` | an MD5 mismatch, no flash detected, a status register that does not take | rewrite; check the flash wiring |
| ``StubError`` | the stub is missing, for another chip, malformed, or did not start | use `.romOnly`, or another stub |

```swift
do {
    try await esp.writeFlash(regions).value
} catch let error as UsageError {
    print("Refused:", error)
} catch let error as FlashError {
    print("Integrity:", error)
} catch is CancellationError {
    print("Cancelled; the flash is partly written")
}
```

Errors that come from the system or Swift itself pass through unwrapped: `CancellationError`,
and the I/O errors of `Data(contentsOf:)` in your own code.
