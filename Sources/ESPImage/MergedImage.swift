// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// Fusion de plusieurs régions flash en un seul fichier (`merge-bin`).
public enum MergedImage {
    /// Binaire brut à partir de `targetOffset`. Les trous sont remplis de 0xFF ; `padTo` complète
    /// jusqu'à la fin de la flash de cette taille.
    /// - Throws: `ImageError.layout` (régions qui se chevauchent ou sous `targetOffset`),
    ///   `ImageError.invalidHeaderSetting`.
    public static func raw(_ regions: [FlashRegion], chip: ChipFamily,
                           targetOffset: UInt32 = 0, padTo: FlashSize? = nil,
                           headerOverrides: FlashHeaderOverrides = .keep) throws -> Data {
        let sorted = try prepared(regions, chip: chip, overrides: headerOverrides)
        if let low = sorted.first, low.address < targetOffset {
            throw ImageError.layout("la région 0x\(String(low.address, radix: 16)) précède l'offset cible 0x\(String(targetOffset, radix: 16))")
        }
        var out = Data()
        for region in sorted {
            let start = Int(region.address - targetOffset)
            if out.count < start { out.append(Data(repeating: 0xFF, count: start - out.count)) }
            out.append(region.data)
        }
        if let padTo {
            let length = padTo.byteCount - Int(targetOffset)
            if out.count < length { out.append(Data(repeating: 0xFF, count: length - out.count)) }
        }
        return out
    }

    /// Fichier Intel HEX : enregistrements de 16 octets au plus, sans remplissage des trous,
    /// avec des enregistrements d'adresse étendue (type 04) au-delà de 64 Kio.
    public static func intelHex(_ regions: [FlashRegion], chip: ChipFamily,
                                headerOverrides: FlashHeaderOverrides = .keep) throws -> String {
        IntelHex.encode(try prepared(regions, chip: chip, overrides: headerOverrides))
    }

    /// Fichier UF2 : blocs de 512 octets, numérotés pour chaque région. Avec `includeMD5`, chaque
    /// bloc porte l'adresse, la longueur et le MD5 de sa charge utile (extension 0x4000).
    /// - Parameter chunkSize: charge utile par bloc ; par défaut 452 octets avec MD5, 476 sans.
    public static func uf2(_ regions: [FlashRegion], chip: ChipFamily,
                           chunkSize: Int? = nil, includeMD5: Bool = true,
                           headerOverrides: FlashHeaderOverrides = .keep) throws -> Data {
        guard let family = ChipImageTraits(chip).uf2FamilyID else { throw ImageError.unsupportedChip(chip) }
        let capacity = includeMD5 ? 476 - 24 : 476
        let chunk = chunkSize ?? capacity
        guard chunk > 0, chunk <= capacity else {
            throw ImageError.layout("charge utile UF2 de \(chunk) octets (1 à \(capacity))")
        }
        let flags: UInt32 = 0x2000 | (includeMD5 ? 0x4000 : 0)
        var out = Data()
        for region in try prepared(regions, chip: chip, overrides: headerOverrides) {
            let blocks = (region.data.count + chunk - 1) / chunk
            for block in 0..<blocks {
                let start = region.data.startIndex + block * chunk
                let payload = region.data.subdata(in: start..<min(start + chunk, region.data.endIndex))
                let address = region.address + UInt32(block * chunk)
                var data = Data()
                for word in [0x0A32_4655, 0x9E5D_5157, flags, address, UInt32(payload.count),
                             UInt32(block), UInt32(blocks), family] as [UInt32] {
                    data.appendLE32(word)
                }
                data.append(payload)
                if includeMD5 {
                    data.appendLE32(address)
                    data.appendLE32(UInt32(payload.count))
                    data.append(MD5.hash(payload))
                }
                data.append(Data(count: 508 - data.count))
                data.appendLE32(0x0AB1_6F30)
                out.append(data)
            }
        }
        return out
    }

    /// Trie, vérifie les chevauchements et patche l'en-tête du bootloader.
    private static func prepared(_ regions: [FlashRegion], chip: ChipFamily,
                                 overrides: FlashHeaderOverrides) throws -> [FlashRegion] {
        var sorted = regions.sorted { $0.address < $1.address }
        for (a, b) in zip(sorted, sorted.dropFirst()) where Int(a.address) + a.data.count > Int(b.address) {
            throw ImageError.layout("les régions 0x\(String(a.address, radix: 16)) et 0x\(String(b.address, radix: 16)) se chevauchent")
        }
        if overrides != .keep, let index = sorted.firstIndex(where: { $0.address == chip.bootloaderOffset }) {
            _ = try ImageHeader.patch(&sorted[index].data, chip: chip, overrides: overrides, detectedSize: nil)
        }
        return sorted
    }
}

/// Lecture et écriture du format Intel HEX.
public enum IntelHex {
    /// Régions contiguës décrites par le fichier (enregistrements 00, 01, 02, 04 ; 03 et 05 ignorés).
    /// - Throws: `ImageError.malformedIntelHex`.
    public static func parse(_ text: String) throws -> [FlashRegion] {
        var bytes: [(address: UInt32, data: Data)] = []
        var base: UInt32 = 0
        var finished = false
        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let number = index + 1
            guard !line.isEmpty else { continue }
            guard !finished else { throw ImageError.malformedIntelHex(line: number, reason: "données après la fin de fichier") }
            guard line.hasPrefix(":"), let record = decodeHex(line.dropFirst()), record.count >= 5 else {
                throw ImageError.malformedIntelHex(line: number, reason: "enregistrement illisible")
            }
            let count = Int(record[0])
            guard record.count == count + 5 else { throw ImageError.malformedIntelHex(line: number, reason: "longueur incohérente") }
            guard record.reduce(0, { $0 &+ $1 }) == 0 else { throw ImageError.malformedIntelHex(line: number, reason: "somme de contrôle") }
            let offset = UInt32(record[1]) << 8 | UInt32(record[2])
            let payload = record.subdata(in: 4..<4 + count)
            switch record[3] {
            case 0x00: bytes.append((base + offset, payload))
            case 0x01: finished = true
            case 0x02:
                guard count == 2 else { throw ImageError.malformedIntelHex(line: number, reason: "adresse de segment") }
                base = (UInt32(payload[0]) << 8 | UInt32(payload[1])) << 4
            case 0x04:
                guard count == 2 else { throw ImageError.malformedIntelHex(line: number, reason: "adresse étendue") }
                base = (UInt32(payload[0]) << 8 | UInt32(payload[1])) << 16
            case 0x03, 0x05: break
            default: throw ImageError.malformedIntelHex(line: number, reason: "type \(record[3]) inconnu")
            }
        }
        var regions: [FlashRegion] = []
        for chunk in bytes.sorted(by: { $0.address < $1.address }) {
            if let last = regions.last, Int(last.address) + last.data.count == Int(chunk.address) {
                regions[regions.count - 1].data.append(chunk.data)
            } else {
                regions.append(FlashRegion(address: chunk.address, data: chunk.data))
            }
        }
        return regions
    }

    static func encode(_ regions: [FlashRegion]) -> String {
        var lines: [String] = []
        let extended = regions.contains { UInt64($0.address) + UInt64($0.data.count) > 0x1_0000 }
        var high: UInt32?
        for region in regions where !region.data.isEmpty {
            var address = region.address
            var remaining = region.data[...]
            while !remaining.isEmpty {
                if extended && address >> 16 != high {
                    high = address >> 16
                    lines.append(record(type: 0x04, offset: 0, payload: Data([UInt8(address >> 24), UInt8(truncatingIfNeeded: address >> 16)])))
                }
                // Un enregistrement ne traverse pas une frontière de 64 Kio.
                let length = min(16, remaining.count, 0x1_0000 - Int(address & 0xFFFF))
                lines.append(record(type: 0x00, offset: UInt16(address & 0xFFFF), payload: Data(remaining.prefix(length))))
                remaining = remaining.dropFirst(length)
                address += UInt32(length)
            }
        }
        lines.append(":00000001FF")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func record(type: UInt8, offset: UInt16, payload: Data) -> String {
        var bytes = Data([UInt8(payload.count), UInt8(offset >> 8), UInt8(offset & 0xFF), type])
        bytes.append(payload)
        let checksum = UInt8(truncatingIfNeeded: 0x100 - Int(bytes.reduce(0) { $0 &+ $1 }))
        bytes.append(checksum)
        return ":" + bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func decodeHex(_ text: Substring) -> Data? {
        guard text.count % 2 == 0 else { return nil }
        var out = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// Modification des réglages flash de l'en-tête d'une image (octets 2 et 3), partagée par
/// `writeFlash` et `MergedImage`.
package enum ImageHeader {
    /// Patche mode, taille et fréquence, puis recalcule le SHA-256 final si l'image en porte un.
    /// - Parameter detectedSize: taille mesurée sur la puce, pour `FlashSizeSetting.detect`.
    /// - Returns: `true` si l'en-tête a changé.
    package static func patch(_ data: inout Data, chip: ChipFamily, overrides: FlashHeaderOverrides,
                              detectedSize: FlashSize?) throws -> Bool {
        guard overrides != .keep, data.count >= 8, data[data.startIndex] == 0xE9 else { return false }
        let traits = ChipImageTraits(chip)
        let base = data.startIndex
        var mode = data[base + 2], sizeAndFrequency = data[base + 3]
        if case .set(let value) = overrides.mode { mode = ChipImageTraits.code(for: value) }
        let size: FlashSize?
        switch overrides.size {
        case .keep: size = nil
        case .set(let value): size = value
        case .detect:
            guard let detectedSize else { throw ImageError.invalidHeaderSetting("taille de flash non détectée") }
            size = detectedSize
        }
        if let size {
            guard let code = traits.code(for: size) else {
                throw ImageError.invalidHeaderSetting("taille \(size) non encodable pour \(chip)")
            }
            sizeAndFrequency = sizeAndFrequency & 0x0F | code << 4
        }
        if case .set(let frequency) = overrides.frequency {
            guard let code = traits.code(for: frequency) else {
                throw ImageError.invalidHeaderSetting("fréquence \(frequency) non encodable pour \(chip)")
            }
            sizeAndFrequency = sizeAndFrequency & 0xF0 | code
        }
        guard mode != data[base + 2] || sizeAndFrequency != data[base + 3] else { return false }
        data[base + 2] = mode
        data[base + 3] = sizeAndFrequency
        if chip != .esp8266, data.count >= 24, data[base + 23] == 1, let end = imageEnd(data), data.count >= end + 32 {
            data.replaceSubrange((base + end)..<(base + end + 32), with: SHA256.hash(data.prefix(end)))
        }
        return true
    }

    /// Fin d'une image ESP32-x, octet de somme de contrôle compris (avant l'empreinte SHA-256).
    package static func imageEnd(_ data: Data) -> Int? {
        let bytes = Data(data)
        guard bytes.count >= 24 else { return nil }
        var offset = 24
        for _ in 0..<Int(bytes[1]) {
            guard offset + 8 <= bytes.count else { return nil }
            offset += 8 + Int(bytes.readLE32(at: offset + 4))
            guard offset <= bytes.count else { return nil }
        }
        return FirmwareImage.checksumOffset(after: offset) + 1
    }
}
