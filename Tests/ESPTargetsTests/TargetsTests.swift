// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets

@Suite("Base types")
struct TargetsTests {
    @Test func imageChipIDsAreUniqueAndReversible() {
        for chip in ChipFamily.allCases {
            guard let id = chip.imageChipID else {
                #expect(chip == .esp8266)
                continue
            }
            #expect(ChipFamily(imageChipID: id) == chip)
        }
        #expect(ChipFamily(imageChipID: 6) == nil)
    }

    @Test func bootloaderOffsets() {
        #expect(ChipFamily.esp32.bootloaderOffset == 0x1000)
        #expect(ChipFamily.esp32s3.bootloaderOffset == 0x0)
        #expect(ChipFamily.esp32p4.bootloaderOffset == 0x2000)
    }

    @Test func revisionEncodingAndOrder() {
        let revision = ChipRevision(encoded: 301)
        #expect(revision == ChipRevision(major: 3, minor: 1))
        #expect(revision.encoded == 301)
        #expect(revision.description == "v3.1")
        #expect(ChipRevision(major: 0, minor: 2) < ChipRevision(major: 1, minor: 0))
    }

    @Test func macAddressParsingAndFormatting() throws {
        let mac = try #require(MACAddress("24:0a:c4-12:34:56"))
        #expect(mac.description == "24:0A:C4:12:34:56")
        #expect(MACAddress(mac.description) == mac)
        #expect(MACAddress("24:0A:C4:12:34") == nil)
        #expect(MACAddress(bytes: Data([1, 2, 3])) == nil)
    }

    @Test func keyPurposeCodesRoundTrip() {
        for code in UInt8(0)...20 {
            #expect(KeyPurpose(rawCode: code).rawCode == code)
        }
        #expect(KeyPurpose(rawCode: 4) == .xtsAES128Key)
        #expect(KeyPurpose(rawCode: 15) == .unknown(15))
    }

    @Test(arguments: [
        (UInt8(0xEF), UInt8(0x40), UInt8(0x16), FlashSize?.some(.mb4)),
        (0xC8, 0x40, 0x18, .mb16),
        (0x20, 0xBA, 0x20, .mb64),
        (0x1F, 0x86, 0x01, .mb2),       // Adesto: size in the low 5 bits of the type
        (0xEF, 0x40, 0x1C, nil),        // 256 MB: outside FlashSize
        (0xEF, 0x40, 0x42, nil),
    ])
    func jedecSizes(manufacturer: UInt8, type: UInt8, capacity: UInt8, expected: FlashSize?) {
        #expect(FlashSize(jedecManufacturer: manufacturer, type: type, capacity: capacity) == expected)
    }
}
