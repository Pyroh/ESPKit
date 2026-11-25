# Secure Boot and Flash Encryption

Secure Boot signatures and flash encryption, offline: the equivalent of `espsecure`.

## Overview

These types come from the ESPSecure module, which has no I/O. It signs images for Secure Boot v2 (RSA-3072, ECDSA P-256 and P-384),
computes the ESP32's Secure Boot v1 digests and signatures, and reproduces the hardware flash
encryption to pre-encrypt images or read encrypted dumps. Its outputs are byte-identical to
espsecure where the algorithm is deterministic, and espsecure verifies the signatures it makes.

The cryptography comes from swift-crypto. Besides `import ESPKit`, ESPSecure comes as a product of
its own, with ESPTargets, for signing tools that never talk to a chip.

## Topics

### Essentials

- <doc:SigningImages>
- <doc:SecureBootV1Guide>
- <doc:EncryptingOffline>

### Secure Boot v2

- ``SecureBootV2``

### Secure Boot v1

- ``SecureBootV1``

### Flash encryption

- ``FlashEncryption``

### Errors

- ``SecureBootError``
- ``FlashEncryptionError``
