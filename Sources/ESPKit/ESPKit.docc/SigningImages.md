# Signing Images for Secure Boot v2

Generate keys, sign images, compute the eFuse key digest and verify signatures.

## Overview

A Secure Boot v2 image ends with a 4 KiB signature sector holding one to three signature blocks.
Each block carries the image digest, the public key and the signature. The chip checks the
public key against a digest burned into its eFuses, then checks the signature.

```swift
import ESPSecure

let key = try SecureBootV2.SigningKey.generate(.ecdsa256)
try key.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)

let signed = try SecureBootV2.sign(image, with: [key])
try SecureBootV2.verify(signed, publicKey: key.publicKey)

let efuseDigest = key.publicKey.digest      // what to burn as SECURE_BOOT_DIGESTn
```

Build the image with `ImageOptions.securePadding = .v2` (ESPImage) so that the signature sector
lands on an MMU page boundary.

### Keys

``SecureBootV2/SigningKey/init(pemRepresentation:)`` reads RSA-3072 (PKCS#1 or PKCS#8) and ECDSA
P-256 or P-384 (SEC1 or PKCS#8) keys, including those `espsecure generate-signing-key` writes.
``SecureBootV2/PublicKey/init(pemRepresentation:)`` reads public keys.
``SecureBootV2/PublicKey/digest`` is the SHA-256 that goes into the eFuses.

ECDSA P-192 (ESP32-C2) is not supported yet: it throws ``SecureBootError/schemeNotSupported(_:chip:)``.

### Signing elsewhere

Private keys often live in an HSM or a signing service. Conform to ``SecureBootV2/Signer`` and
pass it to the `async` variant of `SecureBootV2.sign(_:with:appendingTo:)`: ESPKit computes the
digest, your signer returns a standard big-endian signature — RSA-PSS (MGF1-SHA-256, 32-byte salt)
or ECDSA r ‖ s — and ESPKit assembles the block.

When the signature is computed in another process entirely, ``SecureBootV2/attach(signature:publicKey:to:)``
inserts it after verifying it.

### Several keys

Pass up to three keys or signers at once, or add blocks to an already signed image with
`appendingTo: true`. ``SecureBootV2/signatureBlocks(in:)`` lists the blocks of an image.
