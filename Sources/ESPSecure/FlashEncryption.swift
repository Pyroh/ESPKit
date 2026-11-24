// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Crypto
import _CryptoExtras
import ESPTargets

/// Offline reproduction of the hardware flash encryption: to pre-encrypt an image at the factory,
/// or to read back an encrypted dump.
public enum FlashEncryption {
    public enum Scheme: Hashable, Sendable, CustomStringConvertible {
        /// ESP32: "inverted" AES-256 with a key tweaked by the address; `cryptConfig` is the
        /// value of the `FLASH_CRYPT_CONFIG` eFuse (4 bits, 0xF once encryption is enabled).
        case esp32(cryptConfig: UInt8 = 0xF)
        /// XTS-AES-128: 256-bit key (two AES-128 keys).
        case xtsAES128
        /// XTS-AES-256: 512-bit key (two AES-256 keys).
        case xtsAES256

        /// The chip's default scheme (`nil` if it has no flash encryption).
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

    /// `address` = flash address where the data will be written (encryption depends on it).
    /// `address` and `data.count` must be multiples of 16 (32 for the ESP32 scheme).
    /// - Throws: `FlashEncryptionError`.
    public static func encrypt(_ data: Data, at address: UInt32, key: Data, scheme: Scheme) throws -> Data {
        try transform(data, at: address, key: key, scheme: scheme, encrypt: true)
    }

    public static func decrypt(_ data: Data, at address: UInt32, key: Data, scheme: Scheme) throws -> Data {
        try transform(data, at: address, key: key, scheme: scheme, encrypt: false)
    }

    private static func transform(_ data: Data, at address: UInt32, key: Data, scheme: Scheme, encrypt: Bool) throws -> Data {
        guard key.count == scheme.keyLength else { throw FlashEncryptionError.invalidKeyLength(key.count, scheme: scheme) }
        let alignment: UInt32 = if case .esp32 = scheme { 32 } else { 16 }
        guard address % alignment == 0, data.count % Int(alignment) == 0 else {
            throw FlashEncryptionError.misaligned(address: address, count: data.count)
        }
        switch scheme {
        case .esp32(let config):
            return try esp32(Data(data), at: address, key: Data(key), config: config, encrypt: encrypt)
        case .xtsAES128, .xtsAES256:
            return try xts(Data(data), at: address, key: Data(key), encrypt: encrypt)
        }
    }

    /// XTS over aligned 128-byte units: each unit is byte-reversed,
    /// encrypted in XTS with the tweak `LE32(unit address)` followed by 12 zeros, then reversed
    /// again. An incomplete unit is placed at its position within the unit.
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

    /// ESP32 scheme. For each 32-byte block, the AES-256 key is tweaked by the block address;
    /// each 16-byte block is reversed, run through AES (decryption to encrypt: the
    /// hardware is "inverted"), then reversed again.
    private static func esp32(_ data: Data, at address: UInt32, key: Data, config: UInt8, encrypt: Bool) throws -> Data {
        var out = Data(capacity: data.count)
        for offset in stride(from: 0, to: data.count, by: 32) {
            let blockKey = SymmetricKey(data: tweakedKey(key, address: address + UInt32(offset), config: config))
            for half in [offset, offset + 16] {
                var block = Array(data[(data.startIndex + half)..<(data.startIndex + half + 16)].reversed())
                if encrypt { try AES.inversePermute(&block, key: blockKey) } else { try AES.permute(&block, key: blockKey) }
                out.append(contentsOf: block.reversed())
            }
        }
        return out
    }

    /// Key bit n (most significant bit of byte 0 first) is flipped if bit
    /// `esp32TweakPattern[n]` of the address is 1, for the bit groups enabled by
    /// `FLASH_CRYPT_CONFIG`: bit i of the config enables group i.
    static func tweakedKey(_ key: Data, address: UInt32, config: UInt8) -> Data {
        var bytes = [UInt8](key)
        let groups = [0, 67, 132, 195, 256]
        for group in 0..<4 where config >> group & 1 == 1 {
            for bit in groups[group]..<groups[group + 1] where address >> esp32TweakPattern[bit] & 1 == 1 {
                bytes[bit / 8] ^= 0x80 >> UInt8(bit % 8)
            }
        }
        return Data(bytes)
    }

    /// Address bit associated with each key bit: the ESP32 hardware table, taken from
    /// espsecure's constants (a hardware fact, not code).
    static let esp32TweakPattern: [UInt32] = {
        let full: [UInt32] = Array((5...23).reversed())
        return full + full + full + Array((5...14).reversed())
            + full + full + full + Array((5...12).reversed())
            + full + full + full + Array((5...10).reversed())
            + full + full + full + Array((5...8).reversed())
    }()

    /// Multiplication by α in GF(2¹²⁸), XTS convention (little-endian, polynomial 0x87).
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
