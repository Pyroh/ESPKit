// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPEfuse

/// Pose `value` sur les bits du champ dans les blocs (poids faible d'abord, comme la lecture).
private func set(_ name: String, to value: UInt64, chip: ChipFamily, in blocks: inout [[UInt32]]) {
    let definition = EfuseTable.table(for: chip)!.definition(named: name)!
    var index = 0
    for range in definition.bits {
        for bit in range.start..<range.start + range.count {
            if value >> UInt64(index) & 1 == 1 { blocks[definition.block][bit / 32] |= 1 << UInt32(bit % 32) }
            index += 1
        }
    }
}

@Suite("Tables d'eFuses")
struct EfuseTableTests {
    @Test(arguments: [ChipFamily.esp32, .esp32s2, .esp32s3, .esp32c2, .esp32c3, .esp32c5, .esp32c6,
                      .esp32c61, .esp32h2, .esp32h21, .esp32h4, .esp32p4])
    func generatedTablesAreConsistent(chip: ChipFamily) async throws {
        let table = try #require(EfuseTable.table(for: chip))
        #expect(!table.fields.isEmpty)
        let names = table.fields.map(\.name)
        #expect(Set(names).count == names.count, "noms en double")
        for field in table.fields {
            for range in field.bits { #expect(range.start >= 0 && range.start + range.count <= 256, "\(field.name)") }
        }
        // Un contrôleur vierge sait tout décoder et produit un JSON valide.
        let controller = EfuseController(virtual: chip)
        #expect(!(await controller.fields()).isEmpty)
        let json = await controller.summaryJSON()
        #expect((try? JSONSerialization.jsonObject(with: json)) != nil)
    }

    @Test func unsupportedChipsHaveNoTable() {
        #expect(EfuseTable.table(for: .esp8266) == nil)
        #expect(EfuseLayout.layout(for: .esp32c3) == nil)
    }
}

@Suite("Contrôleur d'eFuses")
struct EfuseControllerTests {
    @Test func decodesValuesProtectionsAndNamedValues() async throws {
        var blocks = EfuseLayout.blankBlocks(for: .esp32s3)
        set("SPI_BOOT_CRYPT_CNT", to: 1, chip: .esp32s3, in: &blocks)
        set("KEY_PURPOSE_0", to: 4, chip: .esp32s3, in: &blocks)
        set("RD_DIS", to: 1, chip: .esp32s3, in: &blocks)                       // BLOCK_KEY0 illisible
        let wrDisBit = EfuseTable.esp32s3.definition(named: "SPI_BOOT_CRYPT_CNT")!.writeDisableBit!
        set("WR_DIS", to: 1 << UInt64(wrDisBit), chip: .esp32s3, in: &blocks)
        blocks[4] = [0x0403_0201] + Array(repeating: 0, count: 7)
        let controller = EfuseController(virtual: .esp32s3, initialState: EfuseSnapshot(chip: .esp32s3, blocks: blocks))

        let crypt = try #require(await controller.field(EfuseFieldName.ESP32S3.spiBootCryptCnt))
        #expect(crypt.value == .uint(1))
        #expect(crypt.displayValue == "Enable")
        #expect(crypt.isWriteProtected)
        #expect(await controller.field("KEY_PURPOSE_0")?.value == .keyPurpose(.xtsAES128Key))
        #expect(await controller.field("KEY_PURPOSE_0")?.displayValue == "XTS_AES_128_KEY")
        let key = try #require(await controller.field("BLOCK_KEY0"))
        #expect(key.isReadProtected)
        #expect(key.value == .bytes(Data([1, 2, 3, 4] + Array(repeating: 0, count: 28))))
        #expect(await controller.blocks()[4].isReadProtected)
        // Les alias d'ESP-IDF trouvent aussi le champ.
        #expect(await controller.field("KEY0")?.name == "BLOCK_KEY0")
    }

    @Test func convertsS3Calibration() async throws {
        var blocks = EfuseLayout.blankBlocks(for: .esp32s3)
        set("BLK_VERSION_MAJOR", to: 1, chip: .esp32s3, in: &blocks)
        set("TEMP_CALIB", to: 0x18B, chip: .esp32s3, in: &blocks)               // signe + 139
        set("ADC2_INIT_CODE_ATTEN0", to: 0xA3, chip: .esp32s3, in: &blocks)     // signe + 35
        let controller = EfuseController(virtual: .esp32s3, initialState: EfuseSnapshot(chip: .esp32s3, blocks: blocks))
        #expect(await controller.field("TEMP_CALIB")?.displayValue == "-13.9")
        #expect(await controller.field("ADC2_INIT_CODE_ATTEN0")?.displayValue == "-140")
        let calibration = try #require(await controller.adcCalibration())
        #expect(calibration.blockVersion == 100)
        #expect(calibration.values["TEMP_CALIB"] == -13.9)
    }

    @Test func esp32MACCarriesItsCRC() async throws {
        var blocks = EfuseLayout.blankBlocks(for: .esp32)
        blocks[0][1] = 0x1F6F_E718
        blocks[0][2] = 0x006E_08B6
        var controller = EfuseController(virtual: .esp32, initialState: EfuseSnapshot(chip: .esp32, blocks: blocks))
        #expect(await controller.field("MAC")?.displayValue == "08:b6:1f:6f:e7:18 (CRC 0x6e OK)")
        blocks[0][2] = 0x0077_08B6
        controller = EfuseController(virtual: .esp32, initialState: EfuseSnapshot(chip: .esp32, blocks: blocks))
        #expect(await controller.field("MAC")?.displayValue.contains("bad CRC") == true)
        #expect(await controller.customMAC() == nil)
    }

    @Test func reportsCodingErrors() async {
        var errors = [UInt32](repeating: 0, count: 7)
        errors[1] = 0x10                                   // BLOCK0, mot 2
        errors[5] = 0x0000_0082                            // BLOCK1 : 2 octets corrigés ; BLOCK2 : échec
        errors[5] |= 0x8 << 4
        let snapshot = EfuseSnapshot(chip: .esp32s3, blocks: EfuseLayout.blankBlocks(for: .esp32s3), errorRegisters: errors)
        let found = await EfuseController(virtual: .esp32s3, initialState: snapshot).codingErrors()
        #expect(found.contains(EfuseCodingError(block: 0, kind: .repeatMismatch(word: 2, bits: 0x10))))
        #expect(found.contains(EfuseCodingError(block: 1, kind: .reedSolomon(correctedBytes: 2, failed: false))))
        #expect(found.contains(EfuseCodingError(block: 2, kind: .reedSolomon(correctedBytes: 0, failed: true))))
    }

    @Test func tokensRoundTripAndAreReadOnly() async throws {
        var blocks = EfuseLayout.blankBlocks(for: .esp32s3)
        set("SPI_BOOT_CRYPT_CNT", to: 7, chip: .esp32s3, in: &blocks)
        let original = EfuseController(virtual: .esp32s3, initialState: EfuseSnapshot(chip: .esp32s3, blocks: blocks))
        let token = await original.token()
        #expect(token.hasPrefix("EFSR:esp32s3:"))
        let restored = try EfuseController(token: token)
        #expect(restored.isReadOnly)
        #expect(await restored.snapshot() == original.snapshot())
        #expect(throws: EfuseError.malformedToken) { try EfuseController(token: "EFSR:esp32s3:@@@") }
        #expect(throws: EfuseError.malformedToken) { try EfuseController(token: "nope") }
    }

    @Test func pythonStyleJSON() {
        let value = JSONValue.object([("a", .int(1)), ("b", .object([("c", .string("é\"x")), ("d", .null), ("e", .double(-13.9))]))])
        #expect(value.pythonJSON() == "{\n    \"a\": 1,\n    \"b\": {\n        \"c\": \"\\u00e9\\\"x\",\n        \"d\": null,\n        \"e\": -13.9\n    }\n}")
    }
}
