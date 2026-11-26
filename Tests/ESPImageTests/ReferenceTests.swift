// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPImage

// Differential tests against esptool, used as a black box. Skipped unless
// ESPKIT_IMAGE_REFERENCES names a folder produced by Tools/oracle/make-references.sh:
//
//   ESPKIT_IMAGE_REFERENCES=…/ref-v5 swift test --filter ReferenceTests
//
// The manifest's ELF paths are relative to the references' parent folder.

private let referenceFolder = ProcessInfo.processInfo.environment["ESPKIT_IMAGE_REFERENCES"]
    .map { URL(fileURLWithPath: $0) }

private struct Case: CustomTestStringConvertible, Sendable {
    var name: String
    var chip: ChipFamily
    var elf: String
    var arguments: [String]
    var testDescription: String { name }
}

private func cases() -> [Case] {
    guard let referenceFolder,
          let manifest = try? String(contentsOf: referenceFolder.appendingPathComponent("cases.tsv"), encoding: .utf8)
    else { return [] }
    return manifest.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, let chip = ChipFamily(rawValue: fields[1]) else { return nil }
        return Case(name: fields[0], chip: chip, elf: fields[2], arguments: fields[3].split(separator: " ").map(String.init))
    }
}

private func flashSize(_ text: String) -> FlashSize? {
    FlashSize.allCases.first { $0.description == text }
}

private func bytes(_ text: String) -> Int? {
    if text.hasPrefix("0x") { return Int(text.dropFirst(2), radix: 16) }
    if text.hasSuffix("KB") { return Int(text.dropLast(2)).map { $0 * 1024 } }
    if let size = flashSize(text) { return size.byteCount }
    return Int(text)
}

/// Translates esptool arguments into `ImageOptions`.
private func options(_ arguments: [String]) throws -> (ImageOptions, ESP8266ImageVersion?) {
    // esptool defaults: qio, 1 MB, 40 MHz (ESPKit itself defaults to dio).
    var options = ImageOptions()
    options.flashMode = .qio
    var version: ESP8266ImageVersion?
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        func value() throws -> String {
            let next = iterator.next()
            return try #require(next, "no value after \(argument)")
        }
        switch argument {
        case "--flash_mode":
            let mode = try value()
            options.flashMode = try #require([FlashMode.qio, .qout, .dio, .dout].first { "\($0)" == mode })
        case "--flash_freq":
            options.flashFrequency = FlashFrequency(megahertz: try #require(Int(value().dropLast())))
        case "--flash_size": options.flashSize = try #require(flashSize(value()))
        case "--elf-sha256-offset": options.elfSHA256Offset = UInt32(try #require(bytes(value())))
        case "--min-rev-full": options.minRevision = ChipRevision(encoded: try #require(UInt16(value())))
        case "--max-rev-full": options.maxRevision = ChipRevision(encoded: try #require(UInt16(value())))
        case "--dont-append-digest": options.appendSHA256 = false
        case "--secure-pad": options.securePadding = .v1
        case "--secure-pad-v2": options.securePadding = .v2
        case "--use_segments": options.useSegments = true
        case "--ram-only-header": options.ramOnlyHeader = true
        case "--pad-to-size": options.padToMultipleOf = bytes(try value())
        case "--flash-mmu-page-size": options.mmuPageSize = bytes(try value())
        case "--version": version = iterator.next() == "2" ? .v2 : .v1
        default: Issue.record("untranslated esptool argument: \(argument)")
        }
    }
    return (options, version)
}

/// First difference between two binaries, for a readable message.
private func firstDifference(_ a: Data, _ b: Data) -> String {
    if let index = zip(a, b).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
        return "first difference at 0x\(String(index, radix: 16)) (ESPKit \(a.count) B, esptool \(b.count) B)"
    }
    return "lengths \(a.count) / \(b.count)"
}

@Suite("esptool differential", .enabled(if: referenceFolder != nil))
struct ReferenceTests {
    @Test(arguments: cases())
    fileprivate func elf2image(_ testCase: Case) throws {
        let root = try #require(referenceFolder).deletingLastPathComponent()
        let elf = try ELFFile(parsing: Data(contentsOf: root.appendingPathComponent(testCase.elf)))
        let (options, version) = try options(testCase.arguments)
        if testCase.chip == .esp8266 {
            let files = try ImageBuilder.makeESP8266Image(from: elf, version: version ?? .v1, options: options)
            for file in files {
                let name = version == .v2 ? "\(testCase.name).bin" : "\(testCase.name)-\(file.suffix)"
                let expected = try Data(contentsOf: try #require(referenceFolder).appendingPathComponent(name))
                #expect(file.data == expected, "\(name): \(firstDifference(file.data, expected))")
            }
            return
        }
        let image = try ImageBuilder.makeImage(from: elf, chip: testCase.chip, options: options)
        let built = try image.serialized()
        let expected = try Data(contentsOf: try #require(referenceFolder).appendingPathComponent("\(testCase.name).bin"))
        #expect(built == expected, "\(firstDifference(built, expected))")

        // Parsing the reference gives back the same segments and a valid image.
        let parsed = try FirmwareImage(parsing: expected)
        #expect(parsed.validate().isValid, "\(parsed.validate().issues)")
        #expect(parsed.segments.map(\.loadAddress) == image.segments.map(\.loadAddress))
        // Parsing stops at the checksum: the segments a RAM-only header hides are not recovered.
        if !testCase.arguments.contains("--pad-to-size") && !testCase.arguments.contains("--ram-only-header") {
            #expect(try parsed.serialized() == expected)
        }
    }

    @Test(arguments: [ChipFamily.esp32, .esp32s3])
    func mergeBin(chip: ChipFamily) throws {
        let root = try #require(referenceFolder).deletingLastPathComponent()
        let folder = root.appendingPathComponent("elf/idf/\(chip.rawValue)")
        let regions = [
            FlashRegion(address: chip.bootloaderOffset, data: try Data(contentsOf: folder.appendingPathComponent("bootloader.bin"))),
            FlashRegion(address: 0x8000, data: try Data(contentsOf: folder.appendingPathComponent("partitions.bin"))),
            FlashRegion(address: 0x1_0000, data: try Data(contentsOf: folder.appendingPathComponent("firmware.bin"))),
        ]
        let references = try #require(referenceFolder)
        let reference = { (name: String) in try Data(contentsOf: references.appendingPathComponent(name)) }

        let raw = try MergedImage.raw(regions, chip: chip)
        let expectedRaw = try reference("merge-\(chip.rawValue).raw")
        #expect(raw == expectedRaw, "raw: \(firstDifference(raw, expectedRaw))")
        let uf2 = try MergedImage.uf2(regions, chip: chip)
        let expectedUF2 = try reference("merge-\(chip.rawValue).uf2")
        #expect(uf2 == expectedUF2, "uf2: \(firstDifference(uf2, expectedUF2))")
        let hex = try MergedImage.intelHex(regions, chip: chip)
        let expectedHex = String(decoding: try reference("merge-\(chip.rawValue).hex"), as: UTF8.self)
        #expect(hex == expectedHex, "hex: \(firstDifference(Data(hex.utf8), Data(expectedHex.utf8)))")
        // Parsing the HEX gives back the regions.
        #expect(try IntelHex.parse(hex) == regions.sorted { $0.address < $1.address })

        if chip == .esp32 {
            let patched = try MergedImage.raw(regions, chip: chip, targetOffset: 0x1000, padTo: .mb4,
                                              headerOverrides: FlashHeaderOverrides(mode: .set(.qio), frequency: .set(.mhz80),
                                                                                    size: .set(.mb16)))
            let expected = try reference("merge-esp32-patched.raw")
            #expect(patched == expected, "patched: \(firstDifference(patched, expected))")
        }
    }
}
