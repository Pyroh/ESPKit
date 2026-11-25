// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// The three files of an application build, without their flash addresses.
///
/// A build produces a bootloader, a partition table and an application. Only the partition table's
/// address is a build setting (`CONFIG_PARTITION_TABLE_OFFSET`, 0x8000 by default); the others are
/// resolved when the regions are written:
///
/// - the bootloader goes where the chip's ROM looks for it, `ChipFamily.bootloaderOffset`;
/// - the application goes into the partition the bootloader boots: `factory`, or `ota_0` when the
///   table has no factory partition;
/// - if the table has an `otadata` partition, it is erased, so that the bootloader boots that
///   partition rather than one an earlier OTA update selected. `idf.py flash` does the same.
///
/// ```swift
/// let build = FlashRegions(bootloader: bootloader, partitionTable: partitions, application: app)
/// let report = try await esp.writeFlash(build).value
/// ```
public struct FlashRegions: Hashable, Sendable {
    /// The second-stage bootloader (`bootloader.bin`).
    public var bootloader: Data
    /// The binary partition table (`partitions.bin`, `partition-table.bin`).
    public var partitionTable: Data
    /// The application image (`firmware.bin`, `<project>.bin`).
    public var application: Data
    /// Flash offset of the partition table: the build's `CONFIG_PARTITION_TABLE_OFFSET`.
    /// The bootloader looks for the table there, so both must agree.
    public var partitionTableOffset: UInt32

    /// The default partition table offset of ESP-IDF, Arduino and PlatformIO.
    public static let defaultPartitionTableOffset: UInt32 = 0x8000

    /// The files of a build whose partition table is at `partitionTableOffset`.
    public init(bootloader: Data, partitionTable: Data, application: Data,
                partitionTableOffset: UInt32 = FlashRegions.defaultPartitionTableOffset) {
        self.bootloader = bootloader
        self.partitionTable = partitionTable
        self.application = application
        self.partitionTableOffset = partitionTableOffset
    }

    /// The regions to write on `chip`, in address order: bootloader, partition table, the erased
    /// `otadata` partition if the table has one, application.
    ///
    /// `ESPDevice.writeFlash(_:options:)` calls it with the connected chip. Call it yourself to
    /// merge the build into one file, or to verify it after writing.
    ///
    /// - Throws: `PartitionTableError` when the table cannot be read, has no partition to boot,
    ///   or when the files do not fit where they go.
    public func resolved(for chip: ChipFamily) throws -> [FlashRegion] {
        guard partitionTableOffset % 0x1000 == 0 else {
            throw PartitionTableError.layout(
                "the partition table offset \(hex(partitionTableOffset)) is not a multiple of 0x1000")
        }
        let bootloaderEnd = UInt64(chip.bootloaderOffset) + UInt64(bootloader.count)
        guard bootloaderEnd <= partitionTableOffset else {
            throw PartitionTableError.layout(
                "the bootloader (\(hex(chip.bootloaderOffset)) to \(hex(bootloaderEnd))) runs into the partition table at \(hex(partitionTableOffset))")
        }
        let table = try PartitionTable(parsing: partitionTable)
        guard let app = table.bootPartition else { throw PartitionTableError.noApplicationPartition }
        guard application.count <= app.size else {
            throw PartitionTableError.layout(
                "the application (\(application.count) bytes) does not fit in partition \"\(app.label)\" (\(app.size) bytes)")
        }

        var regions = [
            FlashRegion(address: chip.bootloaderOffset, data: bootloader),
            FlashRegion(address: partitionTableOffset, data: partitionTable),
            FlashRegion(address: app.offset, data: application),
        ]
        if let otadata = table.partitions.first(where: { $0.type == PartitionTable.dataType && $0.subtype == PartitionTable.otaDataSubtype }) {
            regions.append(FlashRegion(address: otadata.offset, data: Data(repeating: 0xFF, count: Int(otadata.size))))
        }
        return regions.sorted { $0.address < $1.address }
    }
}

/// A partition table that cannot be read, or a build whose files do not fit its layout.
public enum PartitionTableError: ESPKitError, Equatable {
    /// Not a binary partition table: bad entry magic, MD5 mismatch, table too long…
    case malformed(String)
    /// The table has neither a `factory` nor an `ota_0` application partition.
    case noApplicationPartition
    /// The files overlap or do not fit their partitions.
    case layout(String)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .malformed(let reason): "Invalid partition table: \(reason)"
        case .noApplicationPartition: "The partition table has no factory or ota_0 application partition"
        case .layout(let reason): "Impossible flash layout: \(reason)"
        }
    }
}

/// The binary partition table format of ESP-IDF: 32-byte entries, an optional MD5 entry, then
/// 0xFF up to 0xC00 bytes.
package struct PartitionTable: Hashable, Sendable {
    package struct Partition: Hashable, Sendable {
        package var type: UInt8
        package var subtype: UInt8
        package var offset: UInt32
        package var size: UInt32
        package var label: String
        package var flags: UInt32
    }

    package static let maximumSize = 0xC00
    package static let appType: UInt8 = 0x00
    package static let dataType: UInt8 = 0x01
    package static let factorySubtype: UInt8 = 0x00
    package static let ota0Subtype: UInt8 = 0x10
    package static let otaDataSubtype: UInt8 = 0x00

    package var partitions: [Partition]

    /// The partition the bootloader boots when `otadata` is erased: `factory`, else `ota_0`.
    package var bootPartition: Partition? {
        partitions.first { $0.type == Self.appType && $0.subtype == Self.factorySubtype }
            ?? partitions.first { $0.type == Self.appType && $0.subtype == Self.ota0Subtype }
    }

    package init(parsing data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count <= Self.maximumSize else {
            throw PartitionTableError.malformed("\(bytes.count) bytes, more than the 0xC00 a table can hold")
        }
        var partitions = [Partition]()
        var offset = 0
        var checkedMD5 = false
        while offset + 32 <= bytes.count {
            let entry = bytes[offset ..< offset + 32]
            if entry.allSatisfy({ $0 == 0xFF }) { break }
            switch (entry[offset], entry[offset + 1]) {
            case (0xAA, 0x50):
                partitions.append(Partition(
                    type: entry[offset + 2],
                    subtype: entry[offset + 3],
                    offset: Self.uint32(bytes, at: offset + 4),
                    size: Self.uint32(bytes, at: offset + 8),
                    label: String(decoding: entry[(offset + 12) ..< (offset + 28)].prefix { $0 != 0 }, as: UTF8.self),
                    flags: Self.uint32(bytes, at: offset + 28)))
            case (0xEB, 0xEB):
                let stored = Data(entry[(offset + 16) ..< (offset + 32)])
                guard stored == MD5.hash(Data(bytes[0 ..< offset])) else {
                    throw PartitionTableError.malformed("the MD5 entry does not match the partitions")
                }
                checkedMD5 = true
            default:
                throw PartitionTableError.malformed("entry \(offset / 32) has no partition magic")
            }
            offset += 32
            if checkedMD5 { break }
        }
        guard !partitions.isEmpty else { throw PartitionTableError.malformed("no partition") }
        self.partitions = partitions
    }

    private static func uint32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
}

private func hex<T: BinaryInteger>(_ value: T) -> String { "0x" + String(value, radix: 16) }
