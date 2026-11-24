// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Bootloader protocol opcodes (ROM and stub).
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

    /// Commands that carry a data block, and therefore a checksum.
    package var carriesChecksum: Bool {
        switch self {
        case .flashData, .memData, .flashDeflData, .flashEncryptData: true
        default: false
        }
    }
}

/// Request from the host to the chip.
///
/// ```
///  0      1      2..3        4..7        8..
/// | 0x00 |  op  | len (LE16)| chk (LE32)|   data    |
/// ```
package struct Command: Sendable, Equatable {
    package var opcode: UInt8
    package var payload: Data
    /// Checksum of the carried block; 0 for commands without one.
    package var checksum: UInt32

    package init(opcode: UInt8, payload: Data = Data(), checksum: UInt32 = 0) {
        self.opcode = opcode
        self.payload = payload
        self.checksum = checksum
    }

    package init(_ opcode: Opcode, payload: Data = Data(), checksum: UInt32 = 0) {
        self.init(opcode: opcode.rawValue, payload: payload, checksum: checksum)
    }

    /// Unframed packet (before SLIP).
    package func encoded() -> Data {
        var out = Data(capacity: 8 + payload.count)
        out.append(0x00)
        out.append(opcode)
        out.appendLE(UInt16(truncatingIfNeeded: payload.count))
        out.appendLE(checksum)
        out.append(payload)
        return out
    }

    /// Checksum of a data block: XOR of every byte, seeded with 0xEF.
    package static func checksum(of data: Data) -> UInt32 {
        var value: UInt8 = 0xEF
        for byte in data { value ^= byte }
        return UInt32(value)
    }
}

/// Response from the chip.
///
/// ```
/// | 0x01 |  op  | len (LE16)| val (LE32)| data … | status | error | (reserved) |
/// ```
/// Status bytes end `data`: 2 for the stub and the ESP8266 ROM, 4 for the other ROMs.
package struct Response: Sendable, Equatable {
    package var opcode: UInt8
    package var value: UInt32
    /// Payload **and** status bytes, as received.
    package var body: Data

    package init(opcode: UInt8, value: UInt32, body: Data) {
        self.opcode = opcode
        self.value = value
        self.body = body
    }

    /// Parses an already unframed packet. `nil` if it is not a response (direction ≠ 0x01,
    /// or packet too short).
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

    /// Splits the payload from the status. `statusLength` is 2 or 4.
    /// `nil` if the body is shorter than the status bytes.
    package func split(statusLength: Int) -> (payload: Data, status: UInt8, error: UInt8)? {
        guard body.count >= statusLength, statusLength >= 2 else { return nil }
        let statusStart = body.count - statusLength
        let payload = Data(body.prefix(statusStart))
        return (payload, body[body.startIndex + statusStart], body[body.startIndex + statusStart + 1])
    }
}

// MARK: - Little-endian

extension Data {
    package mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// Reads a little-endian integer at `offset` (relative to the start of `self`).
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
