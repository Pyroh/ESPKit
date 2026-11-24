// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// `elf2image` settings.
public struct ImageOptions: Hashable, Sendable {
    public var flashMode: FlashMode = .dio
    /// `nil`: the chip's default frequency (code 0: 40 MHz, 30 MHz on C2, 24 MHz on H2…).
    public var flashFrequency: FlashFrequency? = nil
    public var flashSize: FlashSize = .mb1
    public var minRevision: ChipRevision = .init(major: 0, minor: 0)
    public var maxRevision: ChipRevision = .init(encoded: 0xFFFF)
    public var securePadding: SecurePadding = .none
    /// Offset in the binary where the ELF's SHA-256 is written (0xB0 for ESP-IDF). The slot
    /// must be zero-filled. `nil`: into the app description's `app_elf_sha256` field
    /// when the ELF has a `.flash.appdesc` section (and without `useSegments`), like esptool.
    public var elfSHA256Offset: UInt32? = nil
    public var appendSHA256: Bool = true
    /// Build from the `PT_LOAD` segments rather than from the sections.
    public var useSegments: Bool = false
    /// 8, 16, 32 or 64 KiB. `nil`: the app description's, otherwise 64 KiB.
    public var mmuPageSize: Int? = nil
    /// Pad the file with 0xFF up to a multiple of this size.
    public var padToMultipleOf: Int? = nil
    /// Announce only the RAM segments in the header. Not supported yet (phase 6).
    public var ramOnlyHeader: Bool = false

    public enum SecurePadding: Hashable, Sendable {
        case none
        /// Secure Boot v1 (ESP32): room for the signature after the image.
        case v1
        /// Secure Boot v2: the signed image ends on an MMU page.
        case v2
    }

    public init() {}
}

public typealias ESP8266ImageVersion = ESP8266Image.Format

/// Building images from an ELF.
public enum ImageBuilder {
    /// The equivalent of `elf2image` for the ESP32 and later chips.
    /// - Throws: `ImageError` (chip without a memory map, impossible layout, setting that cannot be encoded).
    public static func makeImage(from elf: ELFFile, chip: ChipFamily,
                                 options: ImageOptions = .init()) throws -> FirmwareImage {
        guard chip != .esp8266, let chipID = chip.imageChipID else { throw ImageError.unsupportedChip(chip) }
        let traits = ChipImageTraits(chip)
        guard traits.hasMemoryMap else { throw ImageError.unsupportedChip(chip) }
        if options.ramOnlyHeader { throw ImageError.layout("the RAM-only header is not supported yet") }
        if options.securePadding != .none && !options.appendSHA256 {
            throw ImageError.layout("secure padding requires the SHA-256 at the end of the image")
        }

        var pieces = merged(loadablePieces(of: elf, useSegments: options.useSegments), traits: traits)
        let page = try pageSize(options: options, pieces: pieces, traits: traits)

        // Segments served by the MMU on one side, RAM segments on the other, each sorted by address.
        var flash = pieces.filter { traits.isFlashMapped($0.address) }.sorted { $0.address < $1.address }
        var ram = pieces.filter { !traits.isFlashMapped($0.address) }.sorted { $0.address < $1.address }
        pieces = []
        moveToFront(named: ".flash.appdesc", in: &flash)
        moveToFront(named: ".dram0.bootdesc", in: &ram)
        for (a, b) in zip(flash, flash.dropFirst())
        where b.address / UInt32(page) == (a.address + UInt32(a.data.count) - 1) / UInt32(page) {
            throw ImageError.layout("segments 0x\(String(a.address, radix: 16)) and 0x\(String(b.address, radix: 16)) fall in the same MMU page")
        }

        // Layout: each flash segment must satisfy (offset + 8) ≡ address (mod page).
        // The gap before it is filled with the start of the first RAM segment, or else with padding.
        var layout: [Piece] = []
        var offset = 24
        while let next = flash.first {
            let gap = alignmentGap(fileOffset: offset, address: next.address, page: page)
            if gap > 0 {
                let filler: Piece
                if !ram.isEmpty && gap > 8 {
                    filler = ram[0].split(at: gap)
                    if ram[0].data.isEmpty { ram.removeFirst() }
                } else {
                    filler = Piece(address: 0, data: Data(count: gap), name: nil)
                }
                layout.append(filler)
                offset += 8 + filler.data.count
                continue
            }
            var segment = next
            if chip == .esp32 {
                // The ESP32 second-stage bootloader does not map the last page if a flash segment
                // ends within its first 0x24 bytes: the segment is extended.
                let remainder = (offset + 8 + segment.data.count) % page
                if remainder < 0x24 { segment.data.append(Data(count: 0x24 - remainder)) }
            }
            layout.append(segment)
            offset += 8 + segment.data.count
            flash.removeFirst()
        }
        for segment in ram {
            layout.append(segment)
            offset += 8 + segment.data.count
        }
        if options.securePadding != .none {
            let alignPast = (offset + 8) % page
            let afterChecksum = options.securePadding == .v1 ? 32 + 4 + 64 + 12 : 32
            let length = ((page - alignPast - 16 - afterChecksum) % page + page) % page
            layout.append(Piece(address: 0, data: Data(count: length), name: nil))
        }

        if let shaOffset = options.elfSHA256Offset ?? appDescriptionDigestOffset(in: layout, traits: traits) {
            try insert(elf.sha256, at: Int(shaOffset), into: &layout)
        }

        var header = FirmwareImage.ExtendedHeader(chipID: chipID, minRevision: options.minRevision,
                                                  maxRevision: options.maxRevision, hashAppended: options.appendSHA256)
        header.legacyMinRevision = 0
        guard let sizeCode = traits.code(for: options.flashSize) else {
            throw ImageError.invalidHeaderSetting("size \(options.flashSize) cannot be encoded for \(chip)")
        }
        var frequencyCode: UInt8 = 0
        if let frequency = options.flashFrequency {
            guard let code = traits.code(for: frequency) else {
                throw ImageError.invalidHeaderSetting("frequency \(frequency) cannot be encoded for \(chip)")
            }
            frequencyCode = code
        }
        var image = FirmwareImage(chip: chip, entryPoint: elf.entryPoint, flashMode: options.flashMode,
                                  flashFrequencyCode: frequencyCode, flashSizeCode: sizeCode,
                                  segments: layout.map { FirmwareImage.Segment(loadAddress: $0.address, data: $0.data,
                                                                                region: traits.region(of: $0.address)) },
                                  extendedHeader: header)
        image.padToMultipleOf = options.padToMultipleOf
        return image
    }

    /// ESP8266: one or two files depending on the format. v1: "0x00000.bin" (header and RAM
    /// segments) and "0x<offset>.bin" (the raw flash code); v2: a single file with an empty suffix.
    public static func makeESP8266Image(from elf: ELFFile, version: ESP8266ImageVersion,
                                        options: ImageOptions = .init()) throws -> [(suffix: String, data: Data)] {
        let traits = ChipImageTraits(.esp8266)
        let pieces = merged(loadablePieces(of: elf, useSegments: options.useSegments), traits: traits)
        let irom = pieces.filter { traits.region(of: $0.address) == .irom }
        let ram = pieces.filter { traits.region(of: $0.address) != .irom }
        guard irom.count <= 1 else { throw ImageError.layout("several IROM segments") }
        guard let sizeCode = traits.code(for: options.flashSize) else {
            throw ImageError.invalidHeaderSetting("size \(options.flashSize) cannot be encoded for the ESP8266")
        }
        var frequencyCode: UInt8 = 0
        if let frequency = options.flashFrequency {
            guard let code = traits.code(for: frequency) else {
                throw ImageError.invalidHeaderSetting("frequency \(frequency) cannot be encoded for the ESP8266")
            }
            frequencyCode = code
        }
        var image = ESP8266Image(format: version, entryPoint: elf.entryPoint, flashMode: options.flashMode,
                                 flashFrequencyCode: frequencyCode, flashSizeCode: sizeCode,
                                 segments: ram.map { FirmwareImage.Segment(loadAddress: $0.address, data: $0.data,
                                                                            region: traits.region(of: $0.address)) })
        switch version {
        case .v1:
            var files = [(suffix: "0x00000.bin", data: try image.serialized())]
            if let code = irom.first {
                files.append((suffix: String(format: "0x%05x.bin", code.address - 0x4020_0000), data: code.data))
            }
            return files
        case .v2:
            image.iromSegment = irom.first.map { FirmwareImage.Segment(loadAddress: $0.address, data: $0.data, region: .irom) }
            return [(suffix: "", data: try image.serialized())]
        }
    }

    // MARK: Steps

    struct Piece {
        var address: UInt32
        var data: Data
        var name: String?

        /// Detaches the first `count` bytes; the rest stays here, at the following address.
        mutating func split(at count: Int) -> Piece {
            let length = min(count, data.count)
            let head = Piece(address: address, data: data.prefix(length), name: nil)
            data = data.subdata(in: data.startIndex + length..<data.endIndex)
            address += UInt32(length)
            return head
        }
    }

    /// Loadable sections (PROGBITS and init arrays, non-zero address and size),
    /// or PT_LOAD segments. Each piece is padded to 4 bytes.
    static func loadablePieces(of elf: ELFFile, useSegments: Bool) -> [Piece] {
        var pieces: [Piece]
        if useSegments {
            pieces = elf.programHeaders
                .filter { $0.type == ELFFile.ProgramHeader.load && !$0.data.isEmpty }
                .map { Piece(address: $0.physicalAddress, data: $0.data, name: nil) }
        } else {
            let kinds: Set<UInt32> = [ELFFile.Section.progbits, ELFFile.Section.initArray,
                                      ELFFile.Section.finiArray, ELFFile.Section.preinitArray]
            pieces = elf.sections
                .filter { kinds.contains($0.type) && $0.address != 0 && !$0.data.isEmpty }
                .map { Piece(address: $0.address, data: $0.data, name: $0.name) }
        }
        for index in pieces.indices where pieces[index].data.count % 4 != 0 {
            pieces[index].data.append(Data(count: 4 - pieces[index].data.count % 4))
        }
        return pieces
    }

    /// Merges contiguous pieces of the same memory region, in ELF file order.
    static func merged(_ pieces: [Piece], traits: ChipImageTraits) -> [Piece] {
        var result = pieces
        var index = result.count - 1
        while index > 0 {
            let previous = result[index - 1], next = result[index]
            if traits.region(of: previous.address) == traits.region(of: next.address),
               UInt64(previous.address) + UInt64(previous.data.count) == UInt64(next.address) {
                result[index - 1].data.append(next.data)
                result.remove(at: index)
            }
            index -= 1
        }
        return result
    }

    /// MMU page: the option, else the app description field, else deduced from its address, else 64 KiB.
    static func pageSize(options: ImageOptions, pieces: [Piece], traits: ChipImageTraits) throws -> Int {
        if let size = options.mmuPageSize {
            guard traits.mmuPageSizes.contains(size) else {
                throw ImageError.invalidHeaderSetting("\(size / 1024) KiB MMU page impossible on \(traits.chip)")
            }
            return size
        }
        guard let description = pieces.first(where: {
            traits.isFlashMapped($0.address) && $0.data.count >= 4 && $0.data.readLE32(at: 0) == AppDescription.magic
        }) else { return 0x1_0000 }
        if description.data.count > 180, description.data[description.data.startIndex + 180] != 0 {
            return 1 << Int(description.data[description.data.startIndex + 180])
        }
        // App description older than ESP-IDF 5.4: it follows the segment header at the start of a page.
        let start = description.address &- 32
        return traits.mmuPageSizes.first { start % UInt32($0) == 0 } ?? 0x1_0000
    }

    /// File offset of the `app_elf_sha256` field (144 bytes after the start of the app
    /// description). Like esptool, only when the image comes from the sections and the
    /// `.flash.appdesc` section is present: not with `useSegments`.
    private static func appDescriptionDigestOffset(in layout: [Piece], traits: ChipImageTraits) -> UInt32? {
        var offset = 24
        for piece in layout {
            if piece.name == ".flash.appdesc", traits.isFlashMapped(piece.address), piece.data.count >= 176 {
                return UInt32(offset + 8 + 144)
            }
            offset += 8 + piece.data.count
        }
        return nil
    }

    private static func moveToFront(named name: String, in pieces: inout [Piece]) {
        if let index = pieces.firstIndex(where: { $0.name == name }) {
            pieces.insert(pieces.remove(at: index), at: 0)
        }
    }

    /// Bytes to insert before a flash segment so that it lands at the right offset (0 = already aligned).
    /// The segment, like the padding, is preceded by an 8-byte header. The arithmetic matches
    /// esptool's byte for byte, including when it adds a whole page.
    static func alignmentGap(fileOffset: Int, address: UInt32, page: Int) -> Int {
        let alignPast = Int(address % UInt32(page)) - 8
        var gap = (page - fileOffset % page) + alignPast
        if gap == 0 || gap == page { return 0 }
        gap -= 8
        if gap < 0 { gap += page }
        return gap
    }

    private static func insert(_ digest: Data, at fileOffset: Int, into layout: inout [Piece]) throws {
        var offset = 24
        for index in layout.indices {
            let start = offset + 8
            let end = start + layout[index].data.count
            if fileOffset >= start && fileOffset + digest.count <= end {
                let range = (fileOffset - start)..<(fileOffset - start + digest.count)
                let base = layout[index].data.startIndex
                let slot = layout[index].data[(base + range.lowerBound)..<(base + range.upperBound)]
                guard slot.allSatisfy({ $0 == 0 }) else {
                    throw ImageError.layout("the ELF SHA-256 slot (0x\(String(fileOffset, radix: 16))) is not empty")
                }
                layout[index].data.replaceSubrange((base + range.lowerBound)..<(base + range.upperBound), with: digest)
                return
            }
            offset = end
        }
        throw ImageError.layout("the ELF SHA-256 offset 0x\(String(fileOffset, radix: 16)) falls in no segment")
    }
}
