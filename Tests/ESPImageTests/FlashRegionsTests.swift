// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPSupport
import ESPTargets
@testable import ESPImage

/// One partition table entry: type, subtype, offset, size, label.
private typealias PartitionEntry = (type: UInt8, subtype: UInt8, offset: UInt32, size: UInt32, label: String)

/// A binary partition table as ESP-IDF writes it: entries, the MD5 entry, 0xFF up to 0xC00.
private func partitionTable(_ entries: [PartitionEntry], md5: Bool = true) -> Data {
    var data = Data()
    for entry in entries {
        data.append(contentsOf: [0xAA, 0x50, entry.type, entry.subtype])
        for value in [entry.offset, entry.size] {
            data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        var label = Array(entry.label.utf8.prefix(16))
        label += [UInt8](repeating: 0, count: 16 - label.count)
        data.append(contentsOf: label)
        data.append(contentsOf: [0, 0, 0, 0])
    }
    if md5 {
        let digest = MD5.hash(data)
        data.append(contentsOf: [0xEB, 0xEB] + [UInt8](repeating: 0xFF, count: 14))
        data.append(digest)
    }
    data.append(Data(repeating: 0xFF, count: 0xC00 - data.count))
    return data
}

/// ESP-IDF's default single-app table.
private let factoryTable = partitionTable([
    (0x01, 0x02, 0x9000, 0x6000, "nvs"),
    (0x01, 0x01, 0xF000, 0x1000, "phy_init"),
    (0x00, 0x00, 0x1_0000, 0x10_0000, "factory"),
])

/// Arduino's default table: two OTA slots and otadata, no factory partition.
private let otaTable = partitionTable([
    (0x01, 0x02, 0x9000, 0x5000, "nvs"),
    (0x01, 0x00, 0xE000, 0x2000, "otadata"),
    (0x00, 0x10, 0x1_0000, 0x14_0000, "app0"),
    (0x00, 0x11, 0x15_0000, 0x14_0000, "app1"),
    (0x01, 0x82, 0x29_0000, 0x16_0000, "spiffs"),
])

@Suite("Partition table")
struct PartitionTableTests {
    @Test func readsEntriesAndChecksTheMD5() throws {
        let table = try PartitionTable(parsing: otaTable)
        #expect(table.partitions.map(\.label) == ["nvs", "otadata", "app0", "app1", "spiffs"])
        #expect(table.partitions[3].offset == 0x15_0000)
        #expect(table.partitions[3].size == 0x14_0000)
        #expect(table.bootPartition?.label == "app0")
    }

    @Test func prefersTheFactoryPartition() throws {
        let table = try PartitionTable(parsing: partitionTable([
            (0x00, 0x10, 0x1_0000, 0x10_0000, "ota_0"),
            (0x00, 0x00, 0x11_0000, 0x10_0000, "factory"),
        ]))
        #expect(table.bootPartition?.label == "factory")
    }

    @Test func acceptsATableWithoutMD5() throws {
        let table = try PartitionTable(parsing: partitionTable([(0x00, 0x00, 0x1_0000, 0x1000, "factory")], md5: false))
        #expect(table.partitions.count == 1)
    }

    @Test func rejectsAWrongMD5() {
        var data = factoryTable
        data[0x40 + 4] ^= 0x01                    // the factory offset, after the MD5 was computed
        #expect(throws: PartitionTableError.malformed("the MD5 entry does not match the partitions")) {
            try PartitionTable(parsing: data)
        }
    }

    @Test func rejectsWhatIsNotATable() {
        #expect(throws: PartitionTableError.malformed("entry 0 has no partition magic")) {
            try PartitionTable(parsing: Data([0xE9] + [UInt8](repeating: 0, count: 63)))
        }
        #expect(throws: PartitionTableError.malformed("no partition")) {
            try PartitionTable(parsing: Data(repeating: 0xFF, count: 0xC00))
        }
    }
}

@Suite("Flash regions")
struct FlashRegionsTests {
    let bootloader = Data(repeating: 0xB0, count: 0x5000)
    let application = Data(repeating: 0xA0, count: 0x3_0000)

    @Test func placesAFactoryBuild() throws {
        let regions = try FlashRegions(bootloader: bootloader, partitionTable: factoryTable, application: application)
            .resolved(for: .esp32)
        #expect(regions.map(\.address) == [0x1000, 0x8000, 0x1_0000])
        #expect(regions.map(\.data) == [bootloader, factoryTable, application])
    }

    @Test func bootsTheFirstOTASlotAndErasesOtadata() throws {
        let regions = try FlashRegions(bootloader: bootloader, partitionTable: otaTable, application: application)
            .resolved(for: .esp32s3)
        #expect(regions.map(\.address) == [0x0, 0x8000, 0xE000, 0x1_0000])
        #expect(regions[2].data == Data(repeating: 0xFF, count: 0x2000))
        #expect(regions[3].data == application)
    }

    @Test func followsAMovedPartitionTable() throws {
        let table = partitionTable([(0x00, 0x00, 0x2_0000, 0x10_0000, "factory")])
        let regions = try FlashRegions(bootloader: Data(repeating: 0, count: 0x8000), partitionTable: table,
                                       application: application, partitionTableOffset: 0xA000)
            .resolved(for: .esp32c3)
        #expect(regions.map(\.address) == [0x0, 0xA000, 0x2_0000])
    }

    @Test func rejectsFilesThatDoNotFit() {
        let tooBig = Data(repeating: 0, count: 0x10_0001)
        #expect(throws: PartitionTableError.layout(
            "the application (1048577 bytes) does not fit in partition \"factory\" (1048576 bytes)")) {
            try FlashRegions(bootloader: bootloader, partitionTable: factoryTable, application: tooBig).resolved(for: .esp32)
        }
        // 0x1000 + 0x7001 runs past 0x8000 on the ESP32, not on the S3 where the bootloader is at 0.
        let longBootloader = Data(repeating: 0, count: 0x7001)
        #expect(throws: PartitionTableError.layout(
            "the bootloader (0x1000 to 0x8001) runs into the partition table at 0x8000")) {
            try FlashRegions(bootloader: longBootloader, partitionTable: factoryTable, application: application).resolved(for: .esp32)
        }
        #expect(throws: Never.self) {
            try FlashRegions(bootloader: longBootloader, partitionTable: factoryTable, application: application).resolved(for: .esp32s3)
        }
        #expect(throws: PartitionTableError.layout("the partition table offset 0x8800 is not a multiple of 0x1000")) {
            try FlashRegions(bootloader: bootloader, partitionTable: factoryTable, application: application,
                             partitionTableOffset: 0x8800).resolved(for: .esp32)
        }
    }

    @Test func needsAnApplicationPartition() {
        let dataOnly = partitionTable([(0x01, 0x02, 0x9000, 0x6000, "nvs")])
        #expect(throws: PartitionTableError.noApplicationPartition) {
            try FlashRegions(bootloader: bootloader, partitionTable: dataOnly, application: application).resolved(for: .esp32)
        }
    }
}
