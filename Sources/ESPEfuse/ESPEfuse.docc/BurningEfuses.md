# Burning eFuses

Build a plan, check it, then burn it — virtually first.

## Overview

A burned bit never goes back to 0, and some bits lock a chip for good. ESPEfuse separates the
steps:

1. **Build** an ``EfuseBurnPlan``: a plain value listing what to burn.
2. **Check** it with ``EfuseController/preview(_:)``, which validates the plan and lists the words
   that will change, or run it on a virtual controller.
3. **Burn** it with ``EfuseController/burn(_:confirm:)`` and ``BurnConfirmation/irreversible``.

```swift
var plan = EfuseBurnPlan()
plan.writeKey(FlashEncryption.generateKey(for: .xtsAES128), to: .key0, purpose: .xtsAES128Key)
plan.writeKeyDigest(signingKey.publicKey, to: .key1, purpose: .secureBootDigest0)
plan.set(EfuseFieldName.ESP32S3.disUsbJtag, to: .bool(true))

// Try it on a copy of the chip's state.
let rehearsal = EfuseController(virtual: .esp32s3, initialState: await efuses.snapshot())
let report = try await rehearsal.burn(plan, confirm: .irreversible)
print(report.steps.map(\.block))

// Then for real.
let changes = try await efuses.preview(plan)
_ = try await efuses.burn(plan, confirm: .irreversible)
```

### What a plan can do

- ``EfuseBurnPlan/set(_:to:)`` burns a field to a value.
- ``EfuseBurnPlan/writeKey(_:to:purpose:readProtect:writeProtect:)`` writes a key into an empty
  key block, with its purpose; like espefuse, XTS keys are byte-reversed and secret keys are
  read-protected.
- ``EfuseBurnPlan/writeKeyDigest(_:to:purpose:)`` burns the digest of a Secure Boot v2 public key.
- ``EfuseBurnPlan/writeBlockData(_:to:offset:)`` and ``EfuseBurnPlan/burnBits(_:in:)`` write raw
  data or bits.
- ``EfuseBurnPlan/readProtect(_:)`` and ``EfuseBurnPlan/writeProtect(_:)`` set protection bits.
- ``EfuseBurnPlan/setCustomMAC(_:)`` and ``EfuseBurnPlan/setFlashVoltage(_:)`` are shortcuts.

The plan is validated as a whole: an unknown field, a value too wide, a bit that would have to
go back to 0, a write-protected field or a used key block makes ``EfuseError/planInvalid(_:)``
list every problem, and nothing is burned.

### Order

Blocks are burned from the last down to BLOCK0, because BLOCK0 holds the protection bits. The
bits that cut off access (`DIS_DOWNLOAD_MODE`, `ENABLE_SECURITY_DOWNLOAD`…) are burned at the
very end, like espefuse's `--postpone`.

### On a real chip

Real burns are available on the ESP32 with the NONE coding scheme. Each block is programmed on
its own with only its new bits, then every block is read back: a bit the plan did not ask for
stops everything with ``EfuseError/unexpectedBits(block:word:bits:)``, and a bit that did not take
is retried twice before ``EfuseError/verificationFailed(block:)``. Other chips, and the ESP32's
3/4 coding scheme, refuse with ``EfuseError/planInvalid(_:)`` for now.

> Warning: Some bits make a chip unusable for development: the flash encryption counter, Secure
> Boot enable bits, the download-mode disables, and the flash voltage (1.8 V on a 3.3 V flash
> and the chip no longer boots). Rehearse every plan virtually, and try new code on a board you
> can afford to lose.

### The ESP32's 3/4 coding scheme

When `CODING_SCHEME` is 1, BLOCK1 to BLOCK3 hold 24 bytes each: keys are 192 bits and data is
limited to 192 bits, as espefuse enforces. Virtual burns support it; real burns do not yet.
