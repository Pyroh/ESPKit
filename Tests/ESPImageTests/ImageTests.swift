// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPSupport
import ESPTargets
@testable import ESPImage

/// ELF 32 bits minimal : une section par entrée, une table de noms, un segment PT_LOAD par section.
private func makeELF(machine: UInt16 = 94, entry: UInt32,
                     sections: [(name: String, address: UInt32, data: Data, type: UInt32)]) -> Data {
    var names = Data([0])
    var nameOffsets: [UInt32] = []
    for section in sections {
        nameOffsets.append(UInt32(names.count))
        names.append(Data(section.name.utf8) + [0])
    }
    let shstrtabName = UInt32(names.count)
    names.append(Data(".shstrtab".utf8) + [0])

    var body = Data()
    var offsets: [UInt32] = []
    let headerSize = 52, programHeaderSize = 32
    let dataStart = headerSize + programHeaderSize * sections.count
    for section in sections {
        offsets.append(UInt32(dataStart + body.count))
        if section.type != ELFFile.Section.nobits { body.append(section.data) }
    }
    let namesOffset = UInt32(dataStart + body.count)
    body.append(names)
    while body.count % 4 != 0 { body.append(0) }
    let sectionHeadersOffset = UInt32(dataStart + body.count)

    var out = Data([0x7F, 0x45, 0x4C, 0x46, 1, 1, 1, 0]) + Data(count: 8)
    out.appendLE16(2); out.appendLE16(machine); out.appendLE32(1); out.appendLE32(entry)
    out.appendLE32(UInt32(headerSize)); out.appendLE32(sectionHeadersOffset); out.appendLE32(0)
    out.appendLE16(UInt16(headerSize)); out.appendLE16(UInt16(programHeaderSize)); out.appendLE16(UInt16(sections.count))
    out.appendLE16(40); out.appendLE16(UInt16(sections.count + 2)); out.appendLE16(UInt16(sections.count + 1))
    for (index, section) in sections.enumerated() {
        let fileSize = section.type == ELFFile.Section.nobits ? 0 : UInt32(section.data.count)
        for value in [1, offsets[index], section.address, section.address, fileSize, UInt32(section.data.count), 7, 4] as [UInt32] {
            out.appendLE32(value)
        }
    }
    out.append(body)
    out.append(Data(count: 40))                                            // section nulle
    for (index, section) in sections.enumerated() {
        for value in [nameOffsets[index], section.type, 2, section.address, offsets[index],
                      UInt32(section.data.count), 0, 0, 4, 0] as [UInt32] { out.appendLE32(value) }
    }
    for value in [shstrtabName, 3, 0, 0, namesOffset, UInt32(names.count), 0, 0, 1, 0] as [UInt32] { out.appendLE32(value) }
    return out
}

private func filled(_ count: Int, _ byte: UInt8) -> Data { Data(repeating: byte, count: count) }

private let progbits = ELFFile.Section.progbits

@Suite("ELF")
struct ELFTests {
    @Test func parsesSectionsAndSegments() throws {
        let elf = try ELFFile(parsing: makeELF(entry: 0x4008_0000, sections: [
            (".iram0.text", 0x4008_0000, filled(10, 1), progbits),
            (".dram0.bss", 0x3FFB_0000, filled(64, 0), ELFFile.Section.nobits),
        ]))
        #expect(elf.machine == .xtensa)
        #expect(elf.entryPoint == 0x4008_0000)
        #expect(elf.sections.map(\.name).contains(".iram0.text"))
        #expect(elf.sections.first { $0.name == ".dram0.bss" }?.data.isEmpty == true)
        #expect(elf.programHeaders.count == 2)
    }

    @Test func rejectsGarbage() {
        #expect(throws: ImageError.self) { try ELFFile(parsing: Data("not an elf at all, really".utf8)) }
        var truncated = makeELF(entry: 0, sections: [(".text", 0x4008_0000, filled(8, 1), progbits)])
        truncated = truncated.prefix(60)
        #expect(throws: ImageError.self) { try ELFFile(parsing: truncated) }
    }
}

@Suite("elf2image")
struct ImageBuilderTests {
    /// Un segment DROM, un segment IROM et deux segments RAM contigus sur ESP32.
    private func esp32ELF() throws -> ELFFile {
        try ELFFile(parsing: makeELF(entry: 0x4008_0100, sections: [
            (".iram0.vectors", 0x4008_0000, filled(0x400, 0x11), progbits),
            (".iram0.text", 0x4008_0400, filled(0xC000, 0x22), progbits),
            (".dram0.data", 0x3FFB_0000, filled(0x802, 0x33), progbits),
            (".flash.rodata", 0x3F40_0020, filled(0x5000, 0x44), progbits),
            (".flash.text", 0x400D_0020, filled(0x6000, 0x55), progbits),
            (".dram0.bss", 0x3FFB_1000, filled(0x100, 0), ELFFile.Section.nobits),
        ]))
    }

    @Test func alignsFlashSegmentsOnMMUPages() throws {
        let image = try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32)
        let data = try image.serialized()
        let parsed = try FirmwareImage(parsing: data)
        #expect(parsed.validate().isValid, "\(parsed.validate().issues)")
        #expect(parsed.chip == .esp32)
        // Les deux sections IRAM contiguës sont fusionnées puis découpées pour combler le trou.
        let iram = parsed.segments.filter { $0.region == .iram }
        #expect(iram.reduce(0) { $0 + $1.data.count } == 0xC400)
        #expect(iram.count == 2)
        #expect(parsed.segments.contains { $0.loadAddress == 0x3FFB_0000 && $0.data.count == 0x804 })   // aligné sur 4
        // Aucun segment de remplissage : la RAM suffit à combler le trou.
        #expect(!parsed.segments.contains { $0.loadAddress == 0 })
        #expect(parsed.segments.first?.loadAddress == 0x3F40_0020)
    }

    @Test func padsWithZerosWhenRAMIsTooShort() throws {
        let elf = try ELFFile(parsing: makeELF(entry: 0x400D_0020, sections: [
            (".flash.rodata", 0x3F40_0020, filled(0x100, 0x44), progbits),
            (".flash.text", 0x400D_0020, filled(0x100, 0x55), progbits),
        ]))
        let image = try ImageBuilder.makeImage(from: elf, chip: .esp32)
        #expect(image.segments.contains { $0.loadAddress == 0 && $0.region == .padding })
        #expect(try FirmwareImage(parsing: image.serialized()).validate().isValid)
    }

    @Test func writesHeaderSettings() throws {
        var options = ImageOptions()
        options.flashMode = .qio
        options.flashFrequency = .mhz80
        options.flashSize = .mb16
        options.minRevision = ChipRevision(major: 1, minor: 0)
        options.appendSHA256 = false
        let data = try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32, options: options).serialized()
        #expect(data[2] == 0x00)
        #expect(data[3] == 0x4F)
        #expect(data.readLE16(at: 15) == 100)
        #expect(data[23] == 0)
        #expect(data.count % 16 == 0)
        let parsed = try FirmwareImage(parsing: data)
        #expect(parsed.flashSize == .mb16 && parsed.flashFrequency == .mhz80 && parsed.flashMode == .qio)
        #expect(parsed.extendedHeader.minRevision == ChipRevision(major: 1, minor: 0))
    }

    @Test func insertsTheELFDigestInTheAppDescription() throws {
        var description = Data()
        description.appendLE32(AppDescription.magic)
        description.append(Data(count: 12))
        description.append(Data("1.2.3".utf8) + Data(count: 27))
        description.append(Data("demo".utf8) + Data(count: 28))
        description.append(Data(count: 256 - description.count))
        let raw = makeELF(entry: 0x4008_0000, sections: [
            (".flash.appdesc", 0x3F40_0020, description, progbits),
            (".flash.text", 0x400D_0020, filled(0x100, 0x55), progbits),
            (".iram0.text", 0x4008_0000, filled(0x8000, 0x22), progbits),
        ])
        let elf = try ELFFile(parsing: raw)
        let image = try ImageBuilder.makeImage(from: elf, chip: .esp32)
        let data = try image.serialized()
        #expect(data.subdata(in: 0xB0..<0xD0) == SHA256.hash(raw))
        let parsed = try FirmwareImage(parsing: data)
        #expect(parsed.appDescription?.version == "1.2.3")
        #expect(parsed.appDescription?.projectName == "demo")
        #expect(parsed.appDescription?.elfSHA256 == SHA256.hash(raw))
    }

    @Test func refusesTwoFlashSegmentsInOnePage() throws {
        let elf = try ELFFile(parsing: makeELF(entry: 0, sections: [
            (".flash.text", 0x400D_0020, filled(0x100, 0x55), progbits),
            (".flash.more", 0x400D_8000, filled(0x100, 0x66), progbits),
        ]))
        #expect(throws: ImageError.self) { try ImageBuilder.makeImage(from: elf, chip: .esp32) }
    }

    @Test func checksUnsupportedSettings() throws {
        var options = ImageOptions()
        options.mmuPageSize = 0x4000
        #expect(throws: ImageError.self) { try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32s3, options: options) }
        #expect(throws: ImageError.unsupportedChip(.esp32h4)) { try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32h4) }
        #expect(throws: ImageError.unsupportedChip(.esp8266)) { try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp8266) }
        options = ImageOptions()
        options.flashFrequency = .mhz80
        #expect(throws: ImageError.self) { try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32c2, options: options) }
    }

    @Test func detectsCorruption() throws {
        var data = try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32).serialized()
        data[40] ^= 0xFF
        let issues = try FirmwareImage(parsing: data).validate().issues
        #expect(issues.contains { if case .checksumMismatch = $0 { true } else { false } })
        #expect(issues.contains(.digestMismatch))
    }

    @Test func buildsESP8266Images() throws {
        let elf = try ELFFile(parsing: makeELF(entry: 0x4010_0004, sections: [
            (".text", 0x4010_0000, filled(0x300, 0x11), progbits),
            (".data", 0x3FFE_8000, filled(0x41, 0x22), progbits),
            (".irom0.text", 0x4020_1010, filled(0x1234, 0x33), progbits),
        ]))
        let v1 = try ImageBuilder.makeESP8266Image(from: elf, version: .v1)
        #expect(v1.map(\.suffix) == ["0x00000.bin", "0x01010.bin"])
        #expect(v1[1].data.count == 0x1234)
        let ram = try ESP8266Image(parsing: v1[0].data)
        #expect(ram.format == .v1 && ram.segments.count == 2 && ram.validate().isValid)

        let v2 = try ImageBuilder.makeESP8266Image(from: elf, version: .v2)
        let parsed = try ESP8266Image(parsing: v2[0].data)
        #expect(parsed.format == .v2)
        #expect(parsed.iromSegment?.data.count == 0x1240)
        #expect(parsed.validate().isValid)
        #expect(try parsed.serialized() == v2[0].data)
        var corrupted = v2[0].data
        corrupted[20] ^= 1
        #expect(!(try ESP8266Image(parsing: corrupted).validate().isValid))
    }

    @Test func recognisesImageFamilies() throws {
        let esp32 = try ImageBuilder.makeImage(from: esp32ELF(), chip: .esp32).serialized()
        guard case .esp32Family(let image) = try AnyFirmwareImage(parsing: esp32) else {
            Issue.record("image ESP32 non reconnue")
            return
        }
        #expect(image.chip == .esp32)
        let elf = try ELFFile(parsing: makeELF(entry: 0x4010_0004, sections: [(".text", 0x4010_0000, filled(0x40, 1), progbits)]))
        let esp8266 = try ImageBuilder.makeESP8266Image(from: elf, version: .v1)[0].data
        guard case .esp8266 = try AnyFirmwareImage(parsing: esp8266) else {
            Issue.record("image ESP8266 non reconnue")
            return
        }
    }
}

@Suite("Fusion")
struct MergedImageTests {
    private let regions = [
        FlashRegion(address: 0x1_0000, data: filled(40, 0xAB)),
        FlashRegion(address: 0x1000, data: filled(20, 0xCD)),
    ]

    @Test func rawFillsGapsAndPads() throws {
        let raw = try MergedImage.raw(regions, chip: .esp32, targetOffset: 0x1000, padTo: .mb1)
        #expect(raw.count == 0x10_0000 - 0x1000)
        #expect(raw.prefix(20) == filled(20, 0xCD))
        #expect(raw[20] == 0xFF)
        #expect(raw.subdata(in: 0xF000..<0xF028) == filled(40, 0xAB))
        #expect(throws: ImageError.self) { try MergedImage.raw(regions, chip: .esp32, targetOffset: 0x2000) }
        #expect(throws: ImageError.self) {
            try MergedImage.raw([FlashRegion(address: 0, data: filled(16, 1)), FlashRegion(address: 8, data: filled(16, 2))], chip: .esp32)
        }
    }

    @Test func intelHexRoundTrips() throws {
        let hex = try MergedImage.intelHex(regions, chip: .esp32)
        #expect(hex.hasPrefix(":020000040000FA\n"))
        #expect(hex.hasSuffix(":00000001FF\n"))
        #expect(try IntelHex.parse(hex) == regions.sorted { $0.address < $1.address })
    }

    @Test func intelHexRejectsBadRecords() {
        #expect(throws: ImageError.malformedIntelHex(line: 1, reason: "somme de contrôle")) {
            try IntelHex.parse(":0100000000FE\n")
        }
        #expect(throws: ImageError.self) { try IntelHex.parse("garbage\n") }
    }

    @Test func uf2BlocksCarryFamilyAndMD5() throws {
        let uf2 = try MergedImage.uf2([FlashRegion(address: 0x1000, data: filled(1000, 7))], chip: .esp32s3)
        #expect(uf2.count == 3 * 512)
        #expect(uf2.readLE32(at: 0) == 0x0A32_4655)
        #expect(uf2.readLE32(at: 8) == 0x6000)
        #expect(uf2.readLE32(at: 28) == 0xC47E_5767)
        let last = uf2.subdata(in: 1024..<1536)
        #expect(last.readLE32(at: 12) == 0x1000 + 904)          // adresse du dernier bloc
        #expect(last.readLE32(at: 16) == 96)                    // charge utile restante
        #expect(last.subdata(in: 32 + 96 + 8..<32 + 96 + 24) == MD5.hash(filled(96, 7)))
        #expect(last.readLE32(at: 508) == 0x0AB1_6F30)
        #expect(throws: ImageError.unsupportedChip(.esp32h4)) { try MergedImage.uf2(regions, chip: .esp32h4) }
    }

    @Test func patchesTheBootloaderHeader() throws {
        var header = Data([0xE9, 0, 0x02, 0x20]) + Data(count: 28)
        header[23] = 0
        let merged = try MergedImage.raw([FlashRegion(address: 0, data: header)], chip: .esp32s3,
                                         headerOverrides: FlashHeaderOverrides(mode: .set(.qio), size: .set(.mb8)))
        #expect(merged[2] == 0x00)
        #expect(merged[3] == 0x30)
        #expect(throws: ImageError.self) {
            try MergedImage.raw([FlashRegion(address: 0, data: header)], chip: .esp32s3,
                                headerOverrides: FlashHeaderOverrides(size: .detect))
        }
    }
}
