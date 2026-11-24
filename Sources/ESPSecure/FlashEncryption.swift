// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Crypto
import _CryptoExtras
import ESPTargets

/// Reproduction hors ligne du chiffrement flash matériel : pour pré-chiffrer une image en usine,
/// ou relire un dump chiffré.
public enum FlashEncryption {
    public enum Scheme: Hashable, Sendable, CustomStringConvertible {
        /// ESP32 : AES-256 « inversé » avec une clé modifiée selon l'adresse. Pas encore pris en charge.
        case esp32(cryptConfig: UInt8 = 0xF)
        /// XTS-AES-128 : clé de 256 bits (deux clés AES-128).
        case xtsAES128
        /// XTS-AES-256 : clé de 512 bits (deux clés AES-256).
        case xtsAES256

        /// Schéma par défaut de la puce (`nil` si elle n'a pas de chiffrement flash).
        public static func `default`(for chip: ChipFamily) -> Scheme? {
            switch chip {
            case .esp8266: nil
            case .esp32: .esp32()
            default: .xtsAES128
            }
        }

        public var keyLength: Int {
            switch self {
            case .esp32, .xtsAES128: 32
            case .xtsAES256: 64
            }
        }

        public var description: String {
            switch self {
            case .esp32(let config): "ESP32 (FLASH_CRYPT_CONFIG 0x\(String(config, radix: 16)))"
            case .xtsAES128: "XTS-AES-128"
            case .xtsAES256: "XTS-AES-256"
            }
        }
    }

    public static func generateKey(for scheme: Scheme) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<scheme.keyLength).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    /// `address` = adresse flash où les données seront écrites (le chiffrement en dépend).
    /// `address` et `data.count` doivent être des multiples de 16.
    /// - Throws: `FlashEncryptionError`.
    public static func encrypt(_ data: Data, at address: UInt32, key: Data, scheme: Scheme) throws -> Data {
        try transform(data, at: address, key: key, scheme: scheme, encrypt: true)
    }

    public static func decrypt(_ data: Data, at address: UInt32, key: Data, scheme: Scheme) throws -> Data {
        try transform(data, at: address, key: key, scheme: scheme, encrypt: false)
    }

    private static func transform(_ data: Data, at address: UInt32, key: Data, scheme: Scheme, encrypt: Bool) throws -> Data {
        guard key.count == scheme.keyLength else { throw FlashEncryptionError.invalidKeyLength(key.count, scheme: scheme) }
        guard address % 16 == 0, data.count % 16 == 0 else {
            throw FlashEncryptionError.misaligned(address: address, count: data.count)
        }
        switch scheme {
        case .esp32:
            throw FlashEncryptionError.schemeNotSupported(scheme)
        case .xtsAES128, .xtsAES256:
            return try xts(Data(data), at: address, key: Data(key), encrypt: encrypt)
        }
    }

    /// XTS par unités de 128 octets alignées : chaque unité est retournée octet par octet,
    /// chiffrée en XTS avec le tweak `LE32(adresse de l'unité)` suivi de 12 zéros, puis retournée
    /// à nouveau. Une unité incomplète est placée à sa position dans l'unité.
    private static func xts(_ data: Data, at address: UInt32, key: Data, encrypt: Bool) throws -> Data {
        let half = key.count / 2
        let dataKey = SymmetricKey(data: key.prefix(half))
        let tweakKey = SymmetricKey(data: key.suffix(half))
        var out = Data(capacity: data.count)
        var offset = 0
        while offset < data.count {
            let position = address + UInt32(offset)
            let base = position & ~0x7F
            let inner = Int(position - base)
            let length = min(128 - inner, data.count - offset)
            var unit = [UInt8](repeating: 0, count: 128)
            unit.replaceSubrange(inner..<inner + length, with: data[(data.startIndex + offset)..<(data.startIndex + offset + length)])
            unit.reverse()

            var tweak = [UInt8](repeating: 0, count: 16)
            for i in 0..<4 { tweak[i] = UInt8(truncatingIfNeeded: base >> (8 * UInt32(i))) }
            try AES.permute(&tweak, key: tweakKey)
            for block in 0..<8 {
                var chunk = Array(unit[block * 16..<block * 16 + 16])
                for i in 0..<16 { chunk[i] ^= tweak[i] }
                if encrypt { try AES.permute(&chunk, key: dataKey) } else { try AES.inversePermute(&chunk, key: dataKey) }
                for i in 0..<16 { unit[block * 16 + i] = chunk[i] ^ tweak[i] }
                multiplyByAlpha(&tweak)
            }
            unit.reverse()
            out.append(contentsOf: unit[inner..<inner + length])
            offset += length
        }
        return out
    }

    /// Multiplication par α dans GF(2¹²⁸), convention XTS (little-endian, polynôme 0x87).
    private static func multiplyByAlpha(_ tweak: inout [UInt8]) {
        var carry: UInt8 = 0
        for i in 0..<16 {
            let next = tweak[i] >> 7
            tweak[i] = tweak[i] << 1 | carry
            carry = next
        }
        if carry != 0 { tweak[0] ^= 0x87 }
    }
}
