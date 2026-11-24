# Encrypting the Flash Offline

Pre-encrypt images at the factory, or decrypt a flash dump, with the chip's own algorithm.

## Overview

With flash encryption enabled, the chip decrypts the flash transparently with a key held in its
eFuses. ``FlashEncryption`` reproduces that transformation, so you can write ciphertext with a
plain `writeFlash`, or read a dump back:

```swift
import ESPSecure

let scheme = FlashEncryption.Scheme.default(for: .esp32s3)!     // .xtsAES128
let key = FlashEncryption.generateKey(for: scheme)
let ciphertext = try FlashEncryption.encrypt(application, at: 0x10000, key: key, scheme: scheme)
let plaintext = try FlashEncryption.decrypt(ciphertext, at: 0x10000, key: key, scheme: scheme)
```

The address matters: encryption depends on where the data sits in flash.

### Schemes

- ``FlashEncryption/Scheme/xtsAES128`` (32-byte key) and ``FlashEncryption/Scheme/xtsAES256``
  (64-byte key): the ESP32-S2 and later. Data is processed in 128-byte units; address and
  length must be multiples of 16.
- ``FlashEncryption/Scheme/esp32(cryptConfig:)``: the original ESP32, an AES-256 variant whose
  key is tweaked by the address according to the `FLASH_CRYPT_CONFIG` eFuse (0xF once encryption
  is enabled). Address and length must be multiples of 32.

To let the chip encrypt as it writes instead, set `FlashRegion.encrypt` (ESPDevice).
