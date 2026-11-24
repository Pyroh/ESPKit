// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// Image ESP8266 : pas d'en-tête étendu ni de SHA-256.
/// - v1 : en-tête 0xE9 et segments RAM ; le code en flash (IROM) est un fichier brut à part.
/// - v2 : en-tête 0xEA suivi du segment IROM, puis un en-tête 0xE9 et les segments RAM,
///   et enfin un CRC32 de tout le fichier.
public struct ESP8266Image: Hashable, Sendable {
    public enum Format: Hashable, Sendable { case v1, v2 }

    public var format: Format
    public var entryPoint: UInt32
    public var flashMode: FlashMode
    public var flashFrequency: FlashFrequency?
    public var flashSize: FlashSize?
    /// Segments RAM, dans l'ordre du fichier.
    public var segments: [FirmwareImage.Segment]
    /// v2 seulement : le code en flash, rangé en tête du fichier.
    public var iromSegment: FirmwareImage.Segment?

    private var rawSizeCode: UInt8
    private var rawFrequencyCode: UInt8
    private var parsed: Parsed?

    private struct Parsed: Hashable, Sendable {
        var storedChecksum: UInt8
        var storedCRC: UInt32?
        var computedCRC: UInt32?
    }

    init(format: Format, entryPoint: UInt32, flashMode: FlashMode, flashFrequencyCode: UInt8,
         flashSizeCode: UInt8, segments: [FirmwareImage.Segment]) {
        let traits = ChipImageTraits(.esp8266)
        self.format = format
        self.entryPoint = entryPoint
        self.flashMode = flashMode
        self.rawFrequencyCode = flashFrequencyCode
        self.rawSizeCode = flashSizeCode
        self.flashFrequency = traits.frequency(forCode: flashFrequencyCode)
        self.flashSize = traits.size(forCode: flashSizeCode)
        self.segments = segments
    }

    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        let traits = ChipImageTraits(.esp8266)
        guard bytes.count >= 8 else { throw ImageError.malformedImage("moins de 8 octets") }
        var offset = 0
        var irom: FirmwareImage.Segment?
        switch bytes[0] {
        case 0xEA:
            format = .v2
            guard bytes.count >= 16 else { throw ImageError.malformedImage("en-tête v2 tronqué") }
            let length = Int(bytes.readLE32(at: 12))
            guard 16 + length <= bytes.count else { throw ImageError.malformedImage("segment IROM tronqué") }
            irom = FirmwareImage.Segment(loadAddress: bytes.readLE32(at: 8), data: bytes.subdata(in: 16..<16 + length),
                                         region: .irom)
            offset = 16 + length
        case 0xE9:
            format = .v1
        default:
            throw ImageError.malformedImage("magic 0x\(String(bytes[0], radix: 16)) inconnu pour l'ESP8266")
        }
        guard offset + 8 <= bytes.count, bytes[offset] == 0xE9 else { throw ImageError.malformedImage("en-tête 0xE9 absent") }
        guard let mode = ChipImageTraits.mode(forCode: bytes[offset + 2]) else {
            throw ImageError.malformedImage("mode flash \(bytes[offset + 2]) inconnu")
        }
        flashMode = mode
        rawSizeCode = bytes[offset + 3] >> 4
        rawFrequencyCode = bytes[offset + 3] & 0xF
        flashSize = traits.size(forCode: rawSizeCode)
        flashFrequency = traits.frequency(forCode: rawFrequencyCode)
        entryPoint = bytes.readLE32(at: offset + 4)
        let count = Int(bytes[offset + 1])
        offset += 8
        var segments: [FirmwareImage.Segment] = []
        for index in 0..<count {
            guard offset + 8 <= bytes.count else { throw ImageError.malformedImage("en-tête du segment \(index) tronqué") }
            let address = bytes.readLE32(at: offset)
            let length = Int(bytes.readLE32(at: offset + 4))
            guard offset + 8 + length <= bytes.count else { throw ImageError.malformedImage("segment \(index) tronqué") }
            segments.append(.init(loadAddress: address, data: bytes.subdata(in: offset + 8..<offset + 8 + length),
                                  region: traits.region(of: address)))
            offset += 8 + length
        }
        self.segments = segments
        iromSegment = irom
        let checksumOffset = FirmwareImage.checksumOffset(after: offset)
        guard checksumOffset < bytes.count else { throw ImageError.malformedImage("somme de contrôle absente") }
        var parsed = Parsed(storedChecksum: bytes[checksumOffset])
        if format == .v2, checksumOffset + 5 <= bytes.count {
            parsed.storedCRC = bytes.readLE32(at: checksumOffset + 1)
            parsed.computedCRC = Self.crc(bytes.prefix(checksumOffset + 1))
        }
        self.parsed = parsed
    }

    public func validate() -> ImageValidation {
        var issues: [ImageValidation.Issue] = []
        if let parsed {
            if parsed.storedChecksum != checksum {
                issues.append(.checksumMismatch(stored: parsed.storedChecksum, computed: checksum))
            }
            if let stored = parsed.storedCRC, let computed = parsed.computedCRC, stored != computed {
                issues.append(.crcMismatch(stored: stored, computed: computed))
            }
        }
        let loaded = segments.sorted { $0.loadAddress < $1.loadAddress }
        for (a, b) in zip(loaded, loaded.dropFirst())
        where UInt64(a.loadAddress) + UInt64(a.data.count) > UInt64(b.loadAddress) {
            issues.append(.overlappingSegments(a.loadAddress, b.loadAddress))
        }
        return ImageValidation(issues: issues)
    }

    /// Pour la v1, seulement le fichier « 0x00000.bin » : le code IROM est un fichier brut à part.
    public func serialized() throws -> Data {
        let traits = ChipImageTraits(.esp8266)
        var size = rawSizeCode, frequency = rawFrequencyCode
        if let flashSize {
            guard let code = traits.code(for: flashSize) else { throw ImageError.invalidHeaderSetting("taille \(flashSize)") }
            size = code
        }
        if let flashFrequency {
            guard let code = traits.code(for: flashFrequency) else { throw ImageError.invalidHeaderSetting("fréquence \(flashFrequency)") }
            frequency = code
        }
        let flags = [ChipImageTraits.code(for: flashMode), size << 4 | frequency]
        var out = Data()
        if format == .v2 {
            out.append(contentsOf: [0xEA, 4] + flags)
            out.appendLE32(entryPoint)
            if let irom = iromSegment {
                // Le segment IROM est rangé à l'adresse 0 et se termine sur 16 octets.
                var code = irom.data
                if code.count % 16 != 0 { code.append(Data(count: 16 - code.count % 16)) }
                out.appendLE32(0)
                out.appendLE32(UInt32(code.count))
                out.append(code)
            }
        }
        out.append(contentsOf: [0xE9, UInt8(clamping: segments.count)] + flags)
        out.appendLE32(entryPoint)
        for segment in segments {
            out.appendLE32(segment.loadAddress)
            out.appendLE32(UInt32(segment.data.count))
            out.append(segment.data)
        }
        out.append(Data(count: FirmwareImage.checksumOffset(after: out.count) - out.count))
        out.append(checksum)
        if format == .v2 { out.appendLE32(Self.crc(out)) }
        return out
    }

    private var checksum: UInt8 {
        var value: UInt8 = 0xEF
        for segment in segments { for byte in segment.data { value ^= byte } }
        return value
    }

    /// CRC des bootloaders récents du SDK ESP8266 : CRC-32 standard, complémenté si son bit
    /// de poids fort est à 1, incrémenté sinon.
    static func crc(_ data: Data) -> UInt32 {
        let crc = Zlib.crc32(data)
        return crc & 0x8000_0000 != 0 ? crc ^ 0xFFFF_FFFF : crc &+ 1
    }
}

/// Analyse un binaire sans connaître son format à l'avance (l'équivalent d'`image-info`).
public enum AnyFirmwareImage: Hashable, Sendable {
    case esp32Family(FirmwareImage)
    case esp8266(ESP8266Image)

    /// `chip` lève l'ambiguïté quand l'en-tête ne suffit pas (l'ESP8266 n'écrit pas d'ID de puce).
    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data, chip: ChipFamily? = nil) throws {
        guard let first = data.first else { throw ImageError.malformedImage("fichier vide") }
        if first == 0xEA || chip == .esp8266 {
            self = .esp8266(try ESP8266Image(parsing: data))
            return
        }
        if chip != nil {
            self = .esp32Family(try FirmwareImage(parsing: data))
            return
        }
        // Sans indice : l'en-tête étendu des puces ESP32 porte un ID connu et 4 octets réservés nuls.
        let bytes = Data(data)
        if bytes.count >= 24, ChipFamily(imageChipID: bytes.readLE16(at: 12)) != nil,
           bytes[19..<23].allSatisfy({ $0 == 0 }), bytes[23] <= 1 {
            self = .esp32Family(try FirmwareImage(parsing: bytes))
        } else {
            self = .esp8266(try ESP8266Image(parsing: bytes))
        }
    }
}
