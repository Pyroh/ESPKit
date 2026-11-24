// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Minimal unsigned integer (32-bit words, least significant first), just enough for the
/// RSA peripheral's Montgomery parameters: R² mod n and −n⁻¹ mod 2³².
struct BigUInt: Equatable {
    private(set) var words: [UInt32]

    init(words: [UInt32]) {
        self.words = words
        normalize()
    }

    /// Big-endian bytes (the order of standard keys and signatures).
    init(bigEndian bytes: Data) {
        var words = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (index, byte) in bytes.reversed().enumerated() {
            words[index / 4] |= UInt32(byte) << (8 * UInt32(index % 4))
        }
        self.init(words: words)
    }

    private mutating func normalize() {
        while let last = words.last, last == 0 { words.removeLast() }
    }

    /// `count` little-endian bytes, the RSA peripheral's order.
    func littleEndian(count: Int) -> Data {
        var out = Data(count: count)
        for index in 0..<min(count, words.count * 4) {
            out[index] = UInt8(truncatingIfNeeded: words[index / 4] >> (8 * UInt32(index % 4)))
        }
        return out
    }

    static func >= (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.words.count != rhs.words.count { return lhs.words.count > rhs.words.count }
        for index in stride(from: lhs.words.count - 1, through: 0, by: -1) where lhs.words[index] != rhs.words[index] {
            return lhs.words[index] > rhs.words[index]
        }
        return true
    }

    /// `self - other`, with `self >= other`.
    mutating func subtract(_ other: BigUInt) {
        var borrow: UInt64 = 0
        for index in words.indices {
            let subtrahend = UInt64(index < other.words.count ? other.words[index] : 0) + borrow
            let minuend = UInt64(words[index])
            if minuend >= subtrahend {
                words[index] = UInt32(minuend - subtrahend)
                borrow = 0
            } else {
                words[index] = UInt32(minuend + (1 << 32) - subtrahend)
                borrow = 1
            }
        }
        normalize()
    }

    mutating func double() {
        var carry: UInt32 = 0
        for index in words.indices {
            let next = words[index] >> 31
            words[index] = words[index] << 1 | carry
            carry = next
        }
        if carry != 0 { words.append(carry) }
    }

    /// 2^exponent mod modulus, by repeated doubling (exponent ≈ 6,144: fast).
    static func powerOfTwo(_ exponent: Int, modulo modulus: BigUInt) -> BigUInt {
        var value = BigUInt(words: [1])
        if value >= modulus { value.subtract(modulus) }
        for _ in 0..<exponent {
            value.double()
            if value >= modulus { value.subtract(modulus) }
        }
        return value
    }

    /// −self⁻¹ mod 2³² (self odd), by Newton's method.
    var negativeInverseModWord: UInt32 {
        let low = words.first ?? 1
        var inverse = low                       // correct to 3 bits for an odd number
        for _ in 0..<5 { inverse = inverse &* (2 &- low &* inverse) }
        return 0 &- inverse
    }
}
