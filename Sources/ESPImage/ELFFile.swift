// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport

/// Fichier ELF 32 bits petit-boutiste, tel que le produisent les chaînes Xtensa et RISC-V
/// d'Espressif. Seul ce dont `ImageBuilder` a besoin est lu : sections, segments, symboles.
public struct ELFFile: Sendable {
    public enum Machine: Hashable, Sendable {
        case xtensa, riscv
        case other(UInt16)
    }

    public struct Section: Hashable, Sendable {
        public var name: String
        public var type: UInt32
        public var flags: UInt32
        public var address: UInt32
        /// Contenu ; vide pour une section NOBITS (`.bss`).
        public var data: Data
        public var size: UInt32

        public static let progbits: UInt32 = 1
        public static let nobits: UInt32 = 8
        public static let initArray: UInt32 = 14
        public static let finiArray: UInt32 = 15
        public static let preinitArray: UInt32 = 16
    }

    public struct ProgramHeader: Hashable, Sendable {
        public var type: UInt32
        public var virtualAddress: UInt32
        public var physicalAddress: UInt32
        public var data: Data
        public var memorySize: UInt32

        public static let load: UInt32 = 1
    }

    public struct Symbol: Hashable, Sendable {
        public var name: String
        public var value: UInt32
        public var size: UInt32
    }

    public var machine: Machine
    public var entryPoint: UInt32
    public var sections: [Section]
    public var programHeaders: [ProgramHeader]
    /// SHA-256 du fichier ELF complet (inséré dans l'app description par `elf2image`).
    public var sha256: Data
    private var symbols: [String: Symbol]

    public func symbol(named name: String) -> Symbol? { symbols[name] }

    /// - Throws: `ImageError.malformedELF`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        guard bytes.count >= 52, bytes.prefix(4) == Data([0x7F, 0x45, 0x4C, 0x46]) else {
            throw ImageError.malformedELF("signature ELF absente")
        }
        guard bytes[4] == 1 else { throw ImageError.malformedELF("seul l'ELF 32 bits est pris en charge") }
        guard bytes[5] == 1 else { throw ImageError.malformedELF("seul l'ELF petit-boutiste est pris en charge") }
        let reader = Reader(bytes)

        let machineCode = try reader.u16(18)
        machine = switch machineCode {
        case 94: .xtensa
        case 243: .riscv
        default: .other(machineCode)
        }
        entryPoint = try reader.u32(24)
        let phOffset = Int(try reader.u32(28))
        let shOffset = Int(try reader.u32(32))
        let phEntrySize = Int(try reader.u16(42))
        let phCount = Int(try reader.u16(44))
        let shEntrySize = Int(try reader.u16(46))
        let shCount = Int(try reader.u16(48))
        let shStringIndex = Int(try reader.u16(50))

        struct RawSection { var nameOffset: UInt32, type: UInt32, flags: UInt32, address: UInt32,
                            offset: UInt32, size: UInt32, link: UInt32, entrySize: UInt32 }
        var raw: [RawSection] = []
        if shOffset != 0 {
            guard shEntrySize >= 40 else { throw ImageError.malformedELF("en-têtes de section de \(shEntrySize) octets") }
            for index in 0..<shCount {
                let base = shOffset + index * shEntrySize
                raw.append(RawSection(nameOffset: try reader.u32(base), type: try reader.u32(base + 4),
                                      flags: try reader.u32(base + 8), address: try reader.u32(base + 12),
                                      offset: try reader.u32(base + 16), size: try reader.u32(base + 20),
                                      link: try reader.u32(base + 24), entrySize: try reader.u32(base + 36)))
            }
        }
        func contents(_ section: RawSection) throws -> Data {
            section.type == Section.nobits ? Data() : try reader.slice(Int(section.offset), Int(section.size))
        }
        let names = shStringIndex < raw.count ? try contents(raw[shStringIndex]) : Data()

        sections = try raw.map { section in
            Section(name: Self.string(in: names, at: Int(section.nameOffset)), type: section.type,
                    flags: section.flags, address: section.address, data: try contents(section), size: section.size)
        }

        var headers: [ProgramHeader] = []
        if phOffset != 0 {
            guard phEntrySize >= 32 else { throw ImageError.malformedELF("en-têtes de programme de \(phEntrySize) octets") }
            for index in 0..<phCount {
                let base = phOffset + index * phEntrySize
                let fileSize = Int(try reader.u32(base + 16))
                headers.append(ProgramHeader(type: try reader.u32(base), virtualAddress: try reader.u32(base + 8),
                                             physicalAddress: try reader.u32(base + 12),
                                             data: try reader.slice(Int(try reader.u32(base + 4)), fileSize),
                                             memorySize: try reader.u32(base + 20)))
            }
        }
        programHeaders = headers

        var table: [String: Symbol] = [:]
        for section in raw where section.type == 2 && Int(section.link) < raw.count {   // SHT_SYMTAB
            let symbolData = try contents(section)
            let strings = try contents(raw[Int(section.link)])
            let entry = max(Int(section.entrySize), 16)
            for start in stride(from: 0, to: symbolData.count - 15, by: entry) {
                let name = Self.string(in: strings, at: Int(symbolData.readLE32(at: start)))
                guard !name.isEmpty else { continue }
                table[name] = Symbol(name: name, value: symbolData.readLE32(at: start + 4),
                                     size: symbolData.readLE32(at: start + 8))
            }
        }
        symbols = table
        sha256 = SHA256.hash(bytes)
    }

    private static func string(in table: Data, at offset: Int) -> String {
        guard offset < table.count else { return "" }
        let start = table.startIndex + offset
        let end = table[start...].firstIndex(of: 0) ?? table.endIndex
        return String(decoding: table[start..<end], as: UTF8.self)
    }

    /// Lecture bornée : toute lecture hors du fichier lève `malformedELF`.
    private struct Reader {
        let data: Data
        init(_ data: Data) { self.data = data }

        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= data.count else { throw ImageError.malformedELF("lecture hors du fichier à \(offset)") }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }

        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { throw ImageError.malformedELF("lecture hors du fichier à \(offset)") }
            return data.readLE32(at: offset)
        }

        func slice(_ offset: Int, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset + count <= data.count else {
                throw ImageError.malformedELF("contenu hors du fichier (\(offset)+\(count))")
            }
            return data.subdata(in: offset..<offset + count)
        }
    }
}

extension Data {
    func readLE32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(self[startIndex + offset + i]) << (8 * i) }
        return value
    }

    func readLE16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    mutating func appendLE32(_ value: UInt32) {
        for i in 0..<4 { append(UInt8(truncatingIfNeeded: value >> (8 * UInt32(i)))) }
    }

    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}
