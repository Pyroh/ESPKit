// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Codage Reed-Solomon RS(44,32) des blocs d'eFuses 1 à 10 (ESP32-S2 et suivantes) :
/// 32 octets de données, 12 octets de parité. Corps GF(2⁸) de polynôme 0x11D, générateur α = 2,
/// racines α⁰ … α¹¹ (codage systématique).
enum ReedSolomon {
    static let parityCount = 12

    private static let tables: (exp: [UInt8], log: [Int]) = {
        var exp = [UInt8](repeating: 0, count: 512)
        var log = [Int](repeating: 0, count: 256)
        var x = 1
        for i in 0..<255 {
            exp[i] = UInt8(x)
            log[x] = i
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x11D }
        }
        for i in 255..<512 { exp[i] = exp[i - 255] }
        return (exp, log)
    }()

    private static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0, b != 0 else { return 0 }
        return tables.exp[tables.log[Int(a)] + tables.log[Int(b)]]
    }

    /// g(x) = ∏ (x − αⁱ), i = 0 … 11, coefficients du degré le plus haut au plus bas.
    private static let generator: [UInt8] = {
        var g: [UInt8] = [1]
        for i in 0..<parityCount {
            var next = [UInt8](repeating: 0, count: g.count + 1)
            for (j, coefficient) in g.enumerated() {
                next[j] ^= coefficient
                next[j + 1] ^= multiply(coefficient, tables.exp[i])
            }
            g = next
        }
        return g
    }()

    /// Les 12 octets de parité de `data` (reste de la division de data·x¹² par g).
    static func parity(for data: Data) -> Data {
        var remainder = [UInt8](repeating: 0, count: parityCount)
        for byte in data {
            let factor = byte ^ remainder[0]
            remainder.removeFirst()
            remainder.append(0)
            if factor != 0 {
                for j in 0..<parityCount { remainder[j] ^= multiply(generator[j + 1], factor) }
            }
        }
        return Data(remainder)
    }
}
