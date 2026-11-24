// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Crypto
import _CryptoExtras

/// ESP32 Secure Boot v1: the bootloader digest checked by the ROM, and the ECDSA P-256
/// signature the bootloader checks on the application. Algorithms from Espressif's
/// Secure Boot v1 documentation; output layout checked against espsecure.
public enum SecureBootV1 {
    /// Size of the digest block written at flash offset 0x0, ahead of the bootloader at 0x1000.
    public static let digestBlockSize = 0x1000

    /// The equivalent of `espsecure digest-secure-bootloader`: the 4 KiB digest block
    /// (IV, SHA-512 digest, 0xFF padding) followed by the bootloader padded with 0xFF to 128 bytes.
    /// The whole result is written at flash offset 0x0.
    ///
    /// Digest: IV and bootloader are padded to 128 bytes; each 16-byte block is reversed,
    /// encrypted in AES-256-ECB with `key` (the 256-bit BLOCK2 key, as stored in the key file),
    /// then reversed again; each 32-bit word of the result is byte-swapped, hashed with SHA-512,
    /// and each 32-bit word of the hash is byte-swapped.
    /// - Parameters:
    ///   - bootloader: the second-stage bootloader image.
    ///   - key: 32 bytes. Keys of the 3/4 coding scheme (24 bytes) are not supported.
    ///   - iv: 128 bytes; `nil`: random.
    /// - Throws: `SecureBootError.invalidKey`.
    public static func digest(bootloader: Data, key: Data, iv: Data? = nil) throws -> Data {
        guard key.count == 32 else { throw SecureBootError.invalidKey("\(key.count)-byte secure boot key; 32 bytes expected") }
        let iv = iv ?? Data((0..<128).map { _ in UInt8.random(in: 0...255) })
        guard iv.count == 128 else { throw SecureBootError.invalidKey("\(iv.count)-byte IV; 128 bytes expected") }

        let padded = paddedTo128(bootloader)
        let plain = Data(iv) + padded
        let aesKey = SymmetricKey(data: key)
        var cipher = Data(capacity: plain.count)
        for offset in stride(from: 0, to: plain.count, by: 16) {
            var block = Array(plain[(plain.startIndex + offset)..<(plain.startIndex + offset + 16)].reversed())
            try AES.permute(&block, key: aesKey)
            cipher.append(contentsOf: block.reversed())
        }
        let hash = Data(Crypto.SHA512.hash(data: swapWords(cipher)))
        var out = Data(iv) + swapWords(hash)
        out.append(Data(repeating: 0xFF, count: digestBlockSize - out.count))
        out.append(padded)
        return out
    }

    /// The equivalent of `espsecure digest-private-key`: SHA-256 of the private scalar
    /// (32 bytes, big-endian), used as the BLOCK2 key in "reflashable" mode. 192 bits for the
    /// 3/4 coding scheme: the first 24 bytes.
    /// - Throws: `SecureBootError.invalidKey` (not an ECDSA P-256 key, `bitLength` other than 192 or 256).
    public static func derivedKey(fromPrivateKeyPEM pem: String, bitLength: Int = 256) throws -> Data {
        guard bitLength == 256 || bitLength == 192 else {
            throw SecureBootError.invalidKey("\(bitLength)-bit derived key; 192 or 256 expected")
        }
        let digest = Data(Crypto.SHA256.hash(data: try privateKey(pem).rawRepresentation))
        return digest.prefix(bitLength / 8)
    }

    /// The equivalent of `espsecure sign-data --version 1`: `data` followed by the 68-byte
    /// signature block (version word 0, then r and s, 32 bytes each, big-endian) over SHA-256(`data`).
    /// - Throws: `SecureBootError.invalidKey`.
    public static func sign(_ data: Data, privateKeyPEM: String) throws -> Data {
        let signature = try privateKey(privateKeyPEM).signature(for: data)
        var out = Data(data)
        out.append(contentsOf: [0, 0, 0, 0])
        out.append(signature.rawRepresentation)
        return out
    }

    /// Checks the signature block at the end of `signed`. `publicKeyPEM` may also be the private key.
    /// - Throws: `SecureBootError.invalidKey`, `.noSignatureBlock`, `.signatureInvalid`.
    public static func verify(_ signed: Data, publicKeyPEM: String) throws {
        let key: P256.Signing.PublicKey
        if let publicKey = try? P256.Signing.PublicKey(pemRepresentation: publicKeyPEM) {
            key = publicKey
        } else {
            key = try privateKey(publicKeyPEM).publicKey
        }
        guard signed.count >= 68 else { throw SecureBootError.noSignatureBlock }
        let body = signed.prefix(signed.count - 68)
        let block = signed.suffix(68)
        guard block.prefix(4) == Data(count: 4) else { throw SecureBootError.noSignatureBlock }
        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: block.suffix(64)),
              key.isValidSignature(signature, for: body) else {
            throw SecureBootError.signatureInvalid
        }
    }

    private static func privateKey(_ pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw SecureBootError.invalidKey("Secure Boot v1 needs an ECDSA P-256 private key in PEM")
        }
    }

    private static func paddedTo128(_ data: Data) -> Data {
        var out = Data(data)
        if out.count % 128 != 0 { out.append(Data(repeating: 0xFF, count: 128 - out.count % 128)) }
        return out
    }

    private static func swapWords(_ data: Data) -> Data {
        var out = Data(capacity: data.count)
        for offset in stride(from: 0, to: data.count, by: 4) {
            out.append(contentsOf: data[(data.startIndex + offset)..<(data.startIndex + offset + 4)].reversed())
        }
        return out
    }
}
