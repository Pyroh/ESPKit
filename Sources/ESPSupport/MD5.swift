// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// MD5 (RFC 1321). Sert uniquement à contrôler l'intégrité des transferts flash,
/// comme le fait la puce : ce n'est pas un usage cryptographique.
package struct MD5: Sendable {
    private var state: (UInt32, UInt32, UInt32, UInt32) = (0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476)
    private var buffer = [UInt8]()
    private var length: UInt64 = 0

    package init() {
        buffer.reserveCapacity(64)
    }

    package static func hash(_ data: Data) -> Data {
        var md5 = MD5()
        md5.update(data)
        return md5.finalize()
    }

    package mutating func update(_ data: Data) {
        length &+= UInt64(data.count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var bytes = raw[...]
            if !buffer.isEmpty {
                let take = min(64 - buffer.count, bytes.count)
                buffer.append(contentsOf: bytes.prefix(take))
                bytes = bytes.dropFirst(take)
                guard buffer.count == 64 else { return }
                buffer.withUnsafeBytes { process(block: UnsafeRawBufferPointer(rebasing: $0[...])) }
                buffer.removeAll(keepingCapacity: true)
            }
            while bytes.count >= 64 {
                process(block: UnsafeRawBufferPointer(rebasing: bytes.prefix(64)))
                bytes = bytes.dropFirst(64)
            }
            buffer.append(contentsOf: bytes)
        }
    }

    package mutating func finalize() -> Data {
        let bitLength = length &* 8
        var tail: [UInt8] = [0x80]
        let used = (buffer.count + 1) % 64
        tail.append(contentsOf: [UInt8](repeating: 0, count: (used <= 56 ? 56 - used : 120 - used)))
        for i in 0..<8 { tail.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i)))) }
        let savedLength = length
        update(Data(tail))
        length = savedLength
        var out = Data(capacity: 16)
        for word in [state.0, state.1, state.2, state.3] {
            for i in 0..<4 { out.append(UInt8(truncatingIfNeeded: word >> (8 * UInt32(i)))) }
        }
        return out
    }

    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    /// K[i] = floor(|sin(i + 1)| × 2³²).
    private static let constants: [UInt32] = (0..<64).map { UInt32(truncatingIfNeeded: Int64(abs(sin(Double($0 + 1))) * 4_294_967_296)) }

    private mutating func process(block: UnsafeRawBufferPointer) {
        var m = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            m[i] = UInt32(block[i * 4]) | UInt32(block[i * 4 + 1]) << 8
                | UInt32(block[i * 4 + 2]) << 16 | UInt32(block[i * 4 + 3]) << 24
        }
        var (a, b, c, d) = state
        for i in 0..<64 {
            var f: UInt32
            let g: Int
            switch i {
            case 0..<16: f = (b & c) | (~b & d); g = i
            case 16..<32: f = (d & b) | (~d & c); g = (5 * i + 1) % 16
            case 32..<48: f = b ^ c ^ d; g = (3 * i + 5) % 16
            default: f = c ^ (b | ~d); g = (7 * i) % 16
            }
            f = f &+ a &+ Self.constants[i] &+ m[g]
            a = d
            d = c
            c = b
            b = b &+ (f << Self.shifts[i] | f >> (32 - Self.shifts[i]))
        }
        state = (state.0 &+ a, state.1 &+ b, state.2 &+ c, state.3 &+ d)
    }
}
