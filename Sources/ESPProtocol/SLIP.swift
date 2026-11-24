// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Encadrement SLIP (RFC 1055) utilisé par le bootloader : chaque paquet est borné par 0xC0,
/// 0xC0 devient 0xDB 0xDC et 0xDB devient 0xDB 0xDD.
package enum SLIP {
    package static let end: UInt8 = 0xC0
    package static let escape: UInt8 = 0xDB
    package static let escapedEnd: UInt8 = 0xDC
    package static let escapedEscape: UInt8 = 0xDD

    /// Encadre `packet` : délimiteur, contenu échappé, délimiteur.
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

/// Reconstitue les paquets SLIP à partir d'un flux d'octets arrivant par morceaux.
///
/// Les octets reçus hors d'un paquet (journal de boot de la ROM, par exemple) sont mis de côté
/// dans `strayBytes`, pour le diagnostic.
package struct SLIPDecoder: Sendable {
    private var current = Data()
    private var inPacket = false
    private var pendingEscape = false

    /// Octets reçus en dehors de tout paquet depuis le dernier `takeStrayBytes()`.
    package private(set) var strayBytes = Data()

    package init() {}

    /// Ajoute des octets et rend les paquets complets qu'ils terminent, dans l'ordre.
    /// - Throws: `SLIPDecodingError.invalidEscape` si 0xDB est suivi d'un octet inattendu.
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
                    // Deux délimiteurs de suite : on reste en début de paquet.
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

    /// Rend et oublie les octets reçus hors paquet.
    package mutating func takeStrayBytes() -> Data {
        defer { strayBytes = Data() }
        return strayBytes
    }

    /// Abandonne le paquet en cours.
    package mutating func reset() {
        current.removeAll(keepingCapacity: true)
        inPacket = false
        pendingEscape = false
    }
}

package enum SLIPDecodingError: Error, Equatable, Sendable {
    case invalidEscape(UInt8)
}
