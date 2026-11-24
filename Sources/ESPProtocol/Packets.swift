// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Opcodes du protocole du bootloader (ROM et stub).
package enum Opcode: UInt8, Sendable, CaseIterable {
    case flashBegin = 0x02
    case flashData = 0x03
    case flashEnd = 0x04
    case memBegin = 0x05
    case memEnd = 0x06
    case memData = 0x07
    case sync = 0x08
    case writeReg = 0x09
    case readReg = 0x0A
    case spiSetParams = 0x0B
    case spiAttach = 0x0D
    case readFlashSlow = 0x0E
    case changeBaudRate = 0x0F
    case flashDeflBegin = 0x10
    case flashDeflData = 0x11
    case flashDeflEnd = 0x12
    case spiFlashMD5 = 0x13
    case getSecurityInfo = 0x14
    case eraseFlash = 0xD0
    case eraseRegion = 0xD1
    case readFlash = 0xD2
    case runUserCode = 0xD3
    case flashEncryptData = 0xD4

    /// Commandes qui transportent un bloc de données et portent donc une somme de contrôle.
    package var carriesChecksum: Bool {
        switch self {
        case .flashData, .memData, .flashDeflData, .flashEncryptData: true
        default: false
        }
    }
}

/// Requête de l'hôte vers la puce.
///
/// ```
///  0      1      2..3        4..7        8..
/// | 0x00 |  op  | len (LE16)| chk (LE32)|   data    |
/// ```
package struct Command: Sendable, Equatable {
    package var opcode: UInt8
    package var payload: Data
    /// Somme de contrôle du bloc transporté ; 0 pour les commandes qui n'en ont pas.
    package var checksum: UInt32

    package init(opcode: UInt8, payload: Data = Data(), checksum: UInt32 = 0) {
        self.opcode = opcode
        self.payload = payload
        self.checksum = checksum
    }

    package init(_ opcode: Opcode, payload: Data = Data(), checksum: UInt32 = 0) {
        self.init(opcode: opcode.rawValue, payload: payload, checksum: checksum)
    }

    /// Paquet non encadré (avant SLIP).
    package func encoded() -> Data {
        var out = Data(capacity: 8 + payload.count)
        out.append(0x00)
        out.append(opcode)
        out.appendLE(UInt16(truncatingIfNeeded: payload.count))
        out.appendLE(checksum)
        out.append(payload)
        return out
    }

    /// Somme de contrôle d'un bloc de données : XOR de tous les octets, valeur initiale 0xEF.
    package static func checksum(of data: Data) -> UInt32 {
        var value: UInt8 = 0xEF
        for byte in data { value ^= byte }
        return UInt32(value)
    }
}

/// Réponse de la puce.
///
/// ```
/// | 0x01 |  op  | len (LE16)| val (LE32)| data … | status | error | (réservés) |
/// ```
/// Les octets d'état terminent `data` : 2 pour le stub et la ROM ESP8266, 4 pour les autres ROM.
package struct Response: Sendable, Equatable {
    package var opcode: UInt8
    package var value: UInt32
    /// Données utiles **et** octets d'état, tels que reçus.
    package var body: Data

    package init(opcode: UInt8, value: UInt32, body: Data) {
        self.opcode = opcode
        self.value = value
        self.body = body
    }

    /// Lit un paquet déjà désencadré. `nil` si ce n'est pas une réponse (direction ≠ 0x01,
    /// ou paquet trop court).
    package init?(packet: Data) {
        guard packet.count >= 8, packet[packet.startIndex] == 0x01 else { return nil }
        let bytes = Data(packet)
        let declared = Int(bytes.readLE(UInt16.self, at: 2))
        let body = bytes.subdata(in: 8..<bytes.count)
        guard body.count >= declared else { return nil }
        self.opcode = bytes[1]
        self.value = bytes.readLE(UInt32.self, at: 4)
        self.body = body.prefix(declared)
    }

    /// Sépare les données utiles et l'état. `statusLength` vaut 2 ou 4.
    /// `nil` si le corps est plus court que les octets d'état.
    package func split(statusLength: Int) -> (payload: Data, status: UInt8, error: UInt8)? {
        guard body.count >= statusLength, statusLength >= 2 else { return nil }
        let statusStart = body.count - statusLength
        let payload = Data(body.prefix(statusStart))
        return (payload, body[body.startIndex + statusStart], body[body.startIndex + statusStart + 1])
    }
}

// MARK: - Petit-boutiste

extension Data {
    package mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Lit un entier petit-boutiste à `offset` (relatif au début de `self`).
    package func readLE<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(self[startIndex + offset + i]) << (8 * i)
        }
        return value
    }

    package static func le<T: FixedWidthInteger>(_ values: T...) -> Data {
        var data = Data()
        for value in values { data.appendLE(value) }
        return data
    }
}
