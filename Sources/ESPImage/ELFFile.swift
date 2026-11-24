// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport

/// 32-bit little-endian ELF file, as produced by Espressif's Xtensa and RISC-V
/// toolchains. Only what `ImageBuilder` needs is read: sections, segments, symbols.
public struct ELFFile: Sendable {
    /// The `e_machine` field.
    public enum Machine: Hashable, Sendable {
        /// Xtensa (94).
        case xtensa
        /// RISC-V (243).
        case riscv
        /// Any other machine, with its code.
        case other(UInt16)
    }

    /// A section header and its contents.
    public struct Section: Hashable, Sendable {
        /// Name from the section string table, for example ".flash.text".
        public var name: String
        /// `sh_type` (see the constants below).
        public var type: UInt32
        /// `sh_flags` (SHF_ALLOC = 0x2…).
        public var flags: UInt32
        /// Load address (`sh_addr`).
        public var address: UInt32
        /// Contents; empty for a NOBITS section (`.bss`).
        public var data: Data
        /// Size in memory (`sh_size`), also for NOBITS sections.
        public var size: UInt32

        /// SHT_PROGBITS: contents stored in the file.
        public static let progbits: UInt32 = 1
        /// SHT_NOBITS: zero-filled at run time, no contents in the file.
        public static let nobits: UInt32 = 8
        /// SHT_INIT_ARRAY.
        public static let initArray: UInt32 = 14
        /// SHT_FINI_ARRAY.
        public static let finiArray: UInt32 = 15
        /// SHT_PREINIT_ARRAY.
        public static let preinitArray: UInt32 = 16
    }

    /// A program header (segment) and its file contents.
    public struct ProgramHeader: Hashable, Sendable {
        /// `p_type` (``load`` for loadable segments).
        public var type: UInt32
        /// Run-time address (`p_vaddr`).
        public var virtualAddress: UInt32
        /// Load address (`p_paddr`).
        public var physicalAddress: UInt32
        /// The `p_filesz` bytes stored in the file.
        public var data: Data
        /// Size in memory (`p_memsz`).
        public var memorySize: UInt32

        /// PT_LOAD.
        public static let load: UInt32 = 1
    }

    /// A symbol of the symbol table.
    public struct Symbol: Hashable, Sendable {
        /// Symbol name.
        public var name: String
        /// Address (`st_value`).
        public var value: UInt32
        /// Size in bytes (`st_size`).
        public var size: UInt32
    }

    /// Target architecture.
    public var machine: Machine
    /// Entry point (`e_entry`).
    public var entryPoint: UInt32
    /// Every section, in file order.
    public var sections: [Section]
    /// Every program header, in file order.
    public var programHeaders: [ProgramHeader]
    /// SHA-256 of the whole ELF file (inserted into the app description by `elf2image`).
    public var sha256: Data
    private var symbols: [String: Symbol]

    /// The symbol called `name`, if the ELF has one.
    public func symbol(named name: String) -> Symbol? { symbols[name] }

    /// Parses a 32-bit little-endian ELF.
    /// - Throws: `ImageError.malformedELF`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        guard bytes.count >= 52, bytes.prefix(4) == Data([0x7F, 0x45, 0x4C, 0x46]) else {
            throw ImageError.malformedELF("missing ELF signature")
        }
        guard bytes[4] == 1 else { throw ImageError.malformedELF("only 32-bit ELF is supported") }
        guard bytes[5] == 1 else { throw ImageError.malformedELF("only little-endian ELF is supported") }
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
            guard shEntrySize >= 40 else { throw ImageError.malformedELF("\(shEntrySize)-byte section headers") }
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
            guard phEntrySize >= 32 else { throw ImageError.malformedELF("\(phEntrySize)-byte program headers") }
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

    /// Bounded reads: any read outside the file throws `malformedELF`.
    private struct Reader {
        let data: Data
        init(_ data: Data) { self.data = data }

        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= data.count else { throw ImageError.malformedELF("read outside the file at \(offset)") }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }

        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= data.count else { throw ImageError.malformedELF("read outside the file at \(offset)") }
            return data.readLE32(at: offset)
        }

        func slice(_ offset: Int, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset + count <= data.count else {
                throw ImageError.malformedELF("contents outside the file (\(offset)+\(count))")
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
