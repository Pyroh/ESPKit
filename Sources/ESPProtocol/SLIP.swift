// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// SLIP framing (RFC 1055) used by the bootloader: each packet is delimited by 0xC0,
/// 0xC0 becomes 0xDB 0xDC and 0xDB becomes 0xDB 0xDD.
package enum SLIP {
    package static let end: UInt8 = 0xC0
    package static let escape: UInt8 = 0xDB
    package static let escapedEnd: UInt8 = 0xDC
    package static let escapedEscape: UInt8 = 0xDD

    /// Frames `packet`: delimiter, escaped content, delimiter.
    package static func encode(_ packet: Data) -> Data {
        var out = Data()
        out.reserveCapacity(packet.count + packet.count / 16 + 2)
        out.append(end)
        for byte in packet {
            switch byte {
            case end: out.append(contentsOf: [escape, escapedEnd])
            case escape: out.append(contentsOf: [escape, escapedEscape])
            default: out.append(byte)
            }
        }
        out.append(end)
        return out
    }
}

/// Rebuilds SLIP packets from a byte stream arriving in pieces.
///
/// Bytes received outside a packet (the ROM boot log, for example) are set aside
/// in `strayBytes`, for diagnostics.
package struct SLIPDecoder: Sendable {
    private var current = Data()
    private var inPacket = false
    private var pendingEscape = false

    /// Bytes received outside any packet since the last `takeStrayBytes()`.
    package private(set) var strayBytes = Data()

    package init() {}

    /// Appends bytes and returns, in order, the packets they complete.
    /// - Throws: `SLIPDecodingError.invalidEscape` if 0xDB is followed by an unexpected byte.
    package mutating func feed(_ bytes: Data) throws(SLIPDecodingError) -> [Data] {
        var packets: [Data] = []
        for byte in bytes {
            guard inPacket else {
                if byte == SLIP.end {
                    inPacket = true
                    current.removeAll(keepingCapacity: true)
                } else {
                    strayBytes.append(byte)
                }
                continue
            }
            if pendingEscape {
                pendingEscape = false
                switch byte {
                case SLIP.escapedEnd: current.append(SLIP.end)
                case SLIP.escapedEscape: current.append(SLIP.escape)
                default:
                    reset()
                    throw .invalidEscape(byte)
                }
                continue
            }
            switch byte {
            case SLIP.escape:
                pendingEscape = true
            case SLIP.end:
                if current.isEmpty {
                    // Two delimiters in a row: stay at the start of a packet.
                    continue
                }
                packets.append(current)
                current = Data()
                inPacket = false
            default:
                current.append(byte)
            }
        }
        return packets
    }

    /// Returns and forgets the bytes received outside a packet.
    package mutating func takeStrayBytes() -> Data {
        defer { strayBytes = Data() }
        return strayBytes
    }

    /// Drops the packet in progress.
    package mutating func reset() {
        current.removeAll(keepingCapacity: true)
        inPacket = false
        pendingEscape = false
    }
}

package enum SLIPDecodingError: Error, Equatable, Sendable {
    case invalidEscape(UInt8)
}
