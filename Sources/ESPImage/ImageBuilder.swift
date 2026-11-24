// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// Réglages d'`elf2image`.
public struct ImageOptions: Hashable, Sendable {
    public var flashMode: FlashMode = .dio
    /// `nil` : fréquence par défaut de la puce (code 0 : 40 MHz, 30 MHz sur C2, 24 MHz sur H2…).
    public var flashFrequency: FlashFrequency? = nil
    public var flashSize: FlashSize = .mb1
    public var minRevision: ChipRevision = .init(major: 0, minor: 0)
    public var maxRevision: ChipRevision = .init(encoded: 0xFFFF)
    public var securePadding: SecurePadding = .none
    /// Offset dans le binaire où écrire le SHA-256 de l'ELF (0xB0 pour ESP-IDF). L'emplacement
    /// doit être rempli de zéros. `nil` : dans le champ `app_elf_sha256` de l'app description
    /// quand l'ELF a une section `.flash.appdesc` (et sans `useSegments`), comme esptool.
    public var elfSHA256Offset: UInt32? = nil
    public var appendSHA256: Bool = true
    /// Construire depuis les segments `PT_LOAD` plutôt que depuis les sections.
    public var useSegments: Bool = false
    /// 8, 16, 32 ou 64 Kio. `nil` : celle de l'app description, sinon 64 Kio.
    public var mmuPageSize: Int? = nil
    /// Compléter le fichier par 0xFF jusqu'à un multiple de cette taille.
    public var padToMultipleOf: Int? = nil
    /// N'annoncer que les segments RAM dans l'en-tête. Pas encore pris en charge (phase 6).
    public var ramOnlyHeader: Bool = false

    public enum SecurePadding: Hashable, Sendable {
        case none
        /// Secure Boot v1 (ESP32) : place pour la signature après l'image.
        case v1
        /// Secure Boot v2 : l'image signée se termine sur une page MMU.
        case v2
    }

    public init() {}
}

public typealias ESP8266ImageVersion = ESP8266Image.Format

/// Construction d'images à partir d'un ELF.
public enum ImageBuilder {
    /// Équivalent d'`elf2image` pour les puces ESP32 et suivantes.
    /// - Throws: `ImageError` (puce sans carte mémoire, disposition impossible, réglage non encodable).
    public static func makeImage(from elf: ELFFile, chip: ChipFamily,
                                 options: ImageOptions = .init()) throws -> FirmwareImage {
        guard chip != .esp8266, let chipID = chip.imageChipID else { throw ImageError.unsupportedChip(chip) }
        let traits = ChipImageTraits(chip)
        guard traits.hasMemoryMap else { throw ImageError.unsupportedChip(chip) }
        if options.ramOnlyHeader { throw ImageError.layout("l'en-tête « RAM seule » n'est pas encore pris en charge") }
        if options.securePadding != .none && !options.appendSHA256 {
            throw ImageError.layout("le remplissage sécurisé suppose le SHA-256 en fin d'image")
        }

        var pieces = merged(loadablePieces(of: elf, useSegments: options.useSegments), traits: traits)
        let page = try pageSize(options: options, pieces: pieces, traits: traits)

        // Segments servis par le MMU d'un côté, segments RAM de l'autre, chacun par adresse.
        var flash = pieces.filter { traits.isFlashMapped($0.address) }.sorted { $0.address < $1.address }
        var ram = pieces.filter { !traits.isFlashMapped($0.address) }.sorted { $0.address < $1.address }
        pieces = []
        moveToFront(named: ".flash.appdesc", in: &flash)
        moveToFront(named: ".dram0.bootdesc", in: &ram)
        for (a, b) in zip(flash, flash.dropFirst())
        where b.address / UInt32(page) == (a.address + UInt32(a.data.count) - 1) / UInt32(page) {
            throw ImageError.layout("les segments 0x\(String(a.address, radix: 16)) et 0x\(String(b.address, radix: 16)) tombent dans la même page MMU")
        }

        // Disposition : chaque segment flash doit vérifier (offset + 8) ≡ adresse (mod page).
        // Le trou avant lui se comble avec le début du premier segment RAM, sinon avec du remplissage.
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
                // Le bootloader de second niveau de l'ESP32 ne mappe pas la dernière page si un
                // segment flash s'y termine dans ses 0x24 premiers octets : on allonge le segment.
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
            throw ImageError.invalidHeaderSetting("taille \(options.flashSize) non encodable pour \(chip)")
        }
        var frequencyCode: UInt8 = 0
        if let frequency = options.flashFrequency {
            guard let code = traits.code(for: frequency) else {
                throw ImageError.invalidHeaderSetting("fréquence \(frequency) non encodable pour \(chip)")
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

    /// ESP8266 : un ou deux fichiers selon le format. v1 : « 0x00000.bin » (en-tête et segments
    /// RAM) et « 0x<offset>.bin » (le code en flash, brut) ; v2 : un seul fichier, suffixe vide.
    public static func makeESP8266Image(from elf: ELFFile, version: ESP8266ImageVersion,
                                        options: ImageOptions = .init()) throws -> [(suffix: String, data: Data)] {
        let traits = ChipImageTraits(.esp8266)
        let pieces = merged(loadablePieces(of: elf, useSegments: options.useSegments), traits: traits)
        let irom = pieces.filter { traits.region(of: $0.address) == .irom }
        let ram = pieces.filter { traits.region(of: $0.address) != .irom }
        guard irom.count <= 1 else { throw ImageError.layout("plusieurs segments IROM") }
        guard let sizeCode = traits.code(for: options.flashSize) else {
            throw ImageError.invalidHeaderSetting("taille \(options.flashSize) non encodable pour l'ESP8266")
        }
        var frequencyCode: UInt8 = 0
        if let frequency = options.flashFrequency {
            guard let code = traits.code(for: frequency) else {
                throw ImageError.invalidHeaderSetting("fréquence \(frequency) non encodable pour l'ESP8266")
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

    // MARK: Étapes

    struct Piece {
        var address: UInt32
        var data: Data
        var name: String?

        /// Détache les `count` premiers octets ; le reste reste ici, à l'adresse suivante.
        mutating func split(at count: Int) -> Piece {
            let length = min(count, data.count)
            let head = Piece(address: address, data: data.prefix(length), name: nil)
            data = data.subdata(in: data.startIndex + length..<data.endIndex)
            address += UInt32(length)
            return head
        }
    }

    /// Sections chargeables (PROGBITS et tableaux d'initialisation, adresse et taille non nulles),
    /// ou segments PT_LOAD. Chaque morceau est complété à 4 octets.
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

    /// Fusionne les morceaux contigus d'une même zone mémoire, dans l'ordre du fichier ELF.
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

    /// Page MMU : option, sinon champ de l'app description, sinon déduite de son adresse, sinon 64 Kio.
    static func pageSize(options: ImageOptions, pieces: [Piece], traits: ChipImageTraits) throws -> Int {
        if let size = options.mmuPageSize {
            guard traits.mmuPageSizes.contains(size) else {
                throw ImageError.invalidHeaderSetting("page MMU de \(size / 1024) Kio impossible sur \(traits.chip)")
            }
            return size
        }
        guard let description = pieces.first(where: {
            traits.isFlashMapped($0.address) && $0.data.count >= 4 && $0.data.readLE32(at: 0) == AppDescription.magic
        }) else { return 0x1_0000 }
        if description.data.count > 180, description.data[description.data.startIndex + 180] != 0 {
            return 1 << Int(description.data[description.data.startIndex + 180])
        }
        // App description d'avant ESP-IDF 5.4 : elle suit l'en-tête de segment en début de page.
        let start = description.address &- 32
        return traits.mmuPageSizes.first { start % UInt32($0) == 0 } ?? 0x1_0000
    }

    /// Offset dans le fichier du champ `app_elf_sha256` (144 octets après le début de l'app
    /// description). Comme esptool, seulement quand l'image vient des sections et que la section
    /// `.flash.appdesc` est présente : pas avec `useSegments`.
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

    /// Octets à intercaler avant un segment flash pour qu'il tombe au bon offset (0 = déjà aligné).
    /// Le segment, comme le remplissage, est précédé d'un en-tête de 8 octets. Le calcul reproduit
    /// celui d'esptool à l'octet près, y compris quand il ajoute une page entière.
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
                    throw ImageError.layout("l'emplacement du SHA-256 de l'ELF (0x\(String(fileOffset, radix: 16))) n'est pas vide")
                }
                layout[index].data.replaceSubrange((base + range.lowerBound)..<(base + range.upperBound), with: digest)
                return
            }
            offset = end
        }
        throw ImageError.layout("l'offset 0x\(String(fileOffset, radix: 16)) du SHA-256 de l'ELF ne tombe dans aucun segment")
    }
}
