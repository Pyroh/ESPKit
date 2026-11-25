// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPDevice

@Suite("SLIP")
struct SLIPTests {
    @Test func encodesDelimitersAndEscapes() {
        let encoded = SLIP.encode(Data([0x01, 0xC0, 0x02, 0xDB, 0x03]))
        #expect(encoded == Data([0xC0, 0x01, 0xDB, 0xDC, 0x02, 0xDB, 0xDD, 0x03, 0xC0]))
    }

    @Test func roundTripsArbitraryBytes() throws {
        let packet = Data((0...255).map(UInt8.init) + [0xC0, 0xDB, 0xC0])
        var decoder = SLIPDecoder()
        #expect(try decoder.feed(SLIP.encode(packet)) == [packet])
    }

    @Test func reassemblesPacketsSplitAcrossReads() throws {
        let stream = SLIP.encode(Data([1, 2, 3])) + SLIP.encode(Data([0xC0, 4]))
        var decoder = SLIPDecoder()
        var packets: [Data] = []
        for byte in stream { packets += try decoder.feed(Data([byte])) }
        #expect(packets == [Data([1, 2, 3]), Data([0xC0, 4])])
    }

    @Test func keepsBytesOutsidePacketsAsStray() throws {
        var decoder = SLIPDecoder()
        let packets = try decoder.feed(Data("boot:0x13\r\n".utf8) + SLIP.encode(Data([9])))
        #expect(packets == [Data([9])])
        #expect(String(decoding: decoder.takeStrayBytes(), as: UTF8.self) == "boot:0x13\r\n")
        #expect(decoder.takeStrayBytes().isEmpty)
    }

    @Test func rejectsInvalidEscape() {
        var decoder = SLIPDecoder()
        #expect(throws: SLIPDecodingError.invalidEscape(0x00)) {
            try decoder.feed(Data([0xC0, 0xDB, 0x00, 0xC0]))
        }
    }

    @Test func ignoresEmptyPacketsBetweenDelimiters() throws {
        var decoder = SLIPDecoder()
        #expect(try decoder.feed(Data([0xC0, 0xC0, 0xC0, 0x05, 0xC0])) == [Data([0x05])])
    }
}

@Suite("Packets")
struct PacketTests {
    @Test func encodesCommandHeader() {
        let command = Command(.readReg, payload: .le(UInt32(0x4000_1000)))
        #expect(command.encoded() == Data([0x00, 0x0A, 0x04, 0x00, 0, 0, 0, 0, 0x00, 0x10, 0x00, 0x40]))
    }

    @Test func checksumIsXorSeededWithEF() {
        #expect(Command.checksum(of: Data()) == 0xEF)
        #expect(Command.checksum(of: Data([0xEF])) == 0)
        #expect(Command.checksum(of: Data([0x01, 0x02, 0x04])) == UInt32(0xEF ^ 0x07))
    }

    @Test func parsesResponseAndSplitsStatus() throws {
        let packet = Data([0x01, 0x0A, 0x04, 0x00, 0x83, 0x1D, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00])
        let response = try #require(Response(packet: packet))
        #expect(response.opcode == 0x0A)
        #expect(response.value == 0x00F0_1D83)
        let split = try #require(response.split(statusLength: 4))
        #expect(split.payload.isEmpty)
        #expect(split.status == 0)
    }

    @Test func splitsPayloadBeforeTwoByteStatus() throws {
        let response = Response(opcode: 0x13, value: 0, body: Data([0xAA, 0xBB, 0x01, 0x05]))
        let split = try #require(response.split(statusLength: 2))
        #expect(split.payload == Data([0xAA, 0xBB]))
        #expect(split.status == 1)
        #expect(split.error == 5)
    }

    @Test func rejectsRequestsAndTruncatedPackets() {
        #expect(Response(packet: Data([0x00, 0x08, 0, 0, 0, 0, 0, 0])) == nil)
        #expect(Response(packet: Data([0x01, 0x08, 0x10, 0x00, 0, 0, 0, 0, 0x00])) == nil)
    }

    @Test func littleEndianHelpers() {
        #expect(Data.le(UInt16(0x1234), UInt16(0xCCDD)) + Data.le(UInt32(0xAABB_CCDD)) == Data([0x34, 0x12, 0xDD, 0xCC, 0xDD, 0xCC, 0xBB, 0xAA]))
        #expect(Data([0x78, 0x56, 0x34, 0x12]).readLE(UInt32.self, at: 0) == 0x1234_5678)
    }
}
