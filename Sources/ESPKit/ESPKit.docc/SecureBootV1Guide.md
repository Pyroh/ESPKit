# Secure Boot v1 on the ESP32

Compute the bootloader digest, derive the BLOCK2 key and sign applications.

## Overview

The original ESP32 Secure Boot (v1) works in two stages. The ROM checks the bootloader against
an AES-based digest keyed by the secret in eFuse BLOCK2; the bootloader then checks each
application's ECDSA P-256 signature.

```swift
import ESPSecure

// Reflashable mode: the BLOCK2 key comes from the signing key.
let blockKey = try SecureBootV1.derivedKey(fromPrivateKeyPEM: pem)

// Digest block (written at 0x0) followed by the bootloader (at 0x1000).
let flashImage = try SecureBootV1.digest(bootloader: bootloader, key: blockKey)

// Application signature, appended to the image.
let signedApp = try SecureBootV1.sign(application, privateKeyPEM: pem)
try SecureBootV1.verify(signedApp, publicKeyPEM: pem)
```

- ``SecureBootV1/digest(bootloader:key:iv:)`` returns the 4 KiB digest block (random IV, SHA-512
  digest, 0xFF padding) followed by the bootloader padded to 128 bytes, like
  `espsecure digest-secure-bootloader`. Pass a fixed `iv` for reproducible output.
- ``SecureBootV1/derivedKey(fromPrivateKeyPEM:bitLength:)`` is the SHA-256 of the private key
  (`espsecure digest-private-key`); 192 bits for the 3/4 coding scheme.
- ``SecureBootV1/sign(_:privateKeyPEM:)`` appends a version word and the 64-byte signature
  (`espsecure sign-data --version 1`).

Keys of the 3/4 coding scheme (24 bytes) are not supported by ``SecureBootV1/digest(bootloader:key:iv:)`` yet.
