// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// Force de sortie des broches SPI de la flash (0 à 15 par broche), dans l'en-tête étendu.
public struct SPIPinDrive: Hashable, Sendable {
    public var clk: UInt8 = 0
    public var q: UInt8 = 0
    public var d: UInt8 = 0
    public var cs: UInt8 = 0
    public var hd: UInt8 = 0
    public var wp: UInt8 = 0

    public init(clk: UInt8 = 0, q: UInt8 = 0, d: UInt8 = 0, cs: UInt8 = 0, hd: UInt8 = 0, wp: UInt8 = 0) {
        self.clk = clk; self.q = q; self.d = d; self.cs = cs; self.hd = hd; self.wp = wp
    }
}

/// Image applicative ou bootloader au format ESP32 (en-tête 0xE9 + en-tête étendu).
public struct FirmwareImage: Hashable, Sendable {
    /// Déduit de l'en-tête étendu ; `nil` si l'ID de puce est inconnu.
    public var chip: ChipFamily?
    public var entryPoint: UInt32
    public var flashMode: FlashMode
    /// `nil` si le code d'en-tête n'est pas connu pour la puce.
    public var flashFrequency: FlashFrequency?
    public var flashSize: FlashSize?
    /// Segments dans l'ordre du fichier.
    public var segments: [Segment]
    public var extendedHeader: ExtendedHeader
    public var appDescription: AppDescription?
    public var bootloaderDescription: BootloaderDescription?
    /// Remplissage final par 0xFF jusqu'à un multiple de cette taille (`--pad-to-size`).
    public var padToMultipleOf: Int?

    public struct Segment: Hashable, Sendable {
        public var loadAddress: UInt32
        public var data: Data
        public var region: MemoryRegion?

        public init(loadAddress: UInt32, data: Data, region: MemoryRegion? = nil) {
            self.loadAddress = loadAddress
            self.data = data
            self.region = region
        }
    }

    public struct ExtendedHeader: Hashable, Sendable {
        /// 0xEE : broche WP désactivée.
        public var wpPin: UInt8 = 0xEE
        public var spiPinDrive = SPIPinDrive()
        /// ID de puce brut (`ChipFamily.imageChipID`).
        public var chipID: UInt16
        public var minRevision: ChipRevision
        public var maxRevision: ChipRevision
        public var hashAppended: Bool
        /// Ancien champ de révision minimale, sur un octet (majeur seulement).
        public var legacyMinRevision: UInt8 = 0

        public init(chipID: UInt16, minRevision: ChipRevision = .init(major: 0, minor: 0),
                    maxRevision: ChipRevision = .init(encoded: 0xFFFF), hashAppended: Bool = true) {
            self.chipID = chipID
            self.minRevision = minRevision
            self.maxRevision = maxRevision
            self.hashAppended = hashAppended
        }
    }

    /// Codes d'en-tête conservés quand la puce ou le code ne se décode pas.
    var rawSizeCode: UInt8 = 0
    var rawFrequencyCode: UInt8 = 0
    /// Ce qu'on a lu dans le fichier, pour `validate()`.
    private var parsed: ParsedFooter?

    private struct ParsedFooter: Hashable, Sendable {
        var storedChecksum: UInt8
        var digestMatches: Bool?
    }

    init(chip: ChipFamily, entryPoint: UInt32, flashMode: FlashMode, flashFrequencyCode: UInt8,
         flashSizeCode: UInt8, segments: [Segment], extendedHeader: ExtendedHeader) {
        let traits = ChipImageTraits(chip)
        self.chip = chip
        self.entryPoint = entryPoint
        self.flashMode = flashMode
        self.flashFrequency = traits.frequency(forCode: flashFrequencyCode)
        self.flashSize = traits.size(forCode: flashSizeCode)
        self.rawFrequencyCode = flashFrequencyCode
        self.rawSizeCode = flashSizeCode
        self.segments = segments
        self.extendedHeader = extendedHeader
        self.appDescription = Self.findAppDescription(in: segments)
        self.bootloaderDescription = segments.first.flatMap { BootloaderDescription(data: $0.data) }
    }

    /// Analyse sans valider les sommes : voir `validate()`.
    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        guard bytes.count >= 24 else { throw ImageError.malformedImage("moins de 24 octets") }
        guard bytes[0] == 0xE9 else { throw ImageError.malformedImage("magic 0x\(String(bytes[0], radix: 16)) au lieu de 0xE9") }
        guard let mode = ChipImageTraits.mode(forCode: bytes[2]) else {
            throw ImageError.malformedImage("mode flash \(bytes[2]) inconnu")
        }
        var header = ExtendedHeader(chipID: bytes.readLE16(at: 12),
                                    minRevision: ChipRevision(encoded: bytes.readLE16(at: 15)),
                                    maxRevision: ChipRevision(encoded: bytes.readLE16(at: 17)),
                                    hashAppended: bytes[23] == 1)
        header.wpPin = bytes[8]
        header.spiPinDrive = SPIPinDrive(clk: bytes[9] & 0xF, q: bytes[9] >> 4, d: bytes[10] & 0xF,
                                         cs: bytes[10] >> 4, hd: bytes[11] & 0xF, wp: bytes[11] >> 4)
        header.legacyMinRevision = bytes[14]

        let chip = ChipFamily(imageChipID: header.chipID)
        let traits = chip.map(ChipImageTraits.init)
        var offset = 24
        var segments: [Segment] = []
        for index in 0..<Int(bytes[1]) {
            guard offset + 8 <= bytes.count else { throw ImageError.malformedImage("en-tête du segment \(index) tronqué") }
            let address = bytes.readLE32(at: offset)
            let length = Int(bytes.readLE32(at: offset + 4))
            guard offset + 8 + length <= bytes.count else { throw ImageError.malformedImage("segment \(index) tronqué") }
            segments.append(Segment(loadAddress: address, data: bytes.subdata(in: offset + 8..<offset + 8 + length),
                                    region: traits?.region(of: address)))
            offset += 8 + length
        }
        let checksumOffset = Self.checksumOffset(after: offset)
        guard checksumOffset < bytes.count else { throw ImageError.malformedImage("somme de contrôle absente") }

        self.chip = chip
        self.entryPoint = bytes.readLE32(at: 4)
        self.flashMode = mode
        self.rawSizeCode = bytes[3] >> 4
        self.rawFrequencyCode = bytes[3] & 0xF
        self.flashSize = traits?.size(forCode: rawSizeCode)
        self.flashFrequency = traits?.frequency(forCode: rawFrequencyCode)
        self.segments = segments
        self.extendedHeader = header
        self.appDescription = Self.findAppDescription(in: segments)
        self.bootloaderDescription = segments.first.flatMap { BootloaderDescription(data: $0.data) }

        var digestMatches: Bool?
        if header.hashAppended {
            let end = checksumOffset + 1
            if end + 32 <= bytes.count {
                digestMatches = SHA256.hash(bytes.prefix(end)) == bytes.subdata(in: end..<end + 32)
            } else {
                digestMatches = false
            }
        }
        parsed = ParsedFooter(storedChecksum: bytes[checksumOffset], digestMatches: digestMatches)
    }

    /// Contrôles : somme de contrôle, SHA-256, chevauchements, alignement MMU des segments flash.
    public func validate() -> ImageValidation {
        var issues: [ImageValidation.Issue] = []
        if let parsed {
            let computed = checksum
            if parsed.storedChecksum != computed {
                issues.append(.checksumMismatch(stored: parsed.storedChecksum, computed: computed))
            }
            if parsed.digestMatches == false { issues.append(.digestMismatch) }
        }
        let loaded = segments.filter { $0.loadAddress != 0 }.sorted { $0.loadAddress < $1.loadAddress }
        for (a, b) in zip(loaded, loaded.dropFirst())
        where UInt64(a.loadAddress) + UInt64(a.data.count) > UInt64(b.loadAddress) {
            issues.append(.overlappingSegments(a.loadAddress, b.loadAddress))
        }
        let page = appDescription?.mmuPageSize ?? 0x1_0000
        var offset = 24
        for segment in segments {
            if segment.region?.isFlashMapped == true, (offset + 8) % page != Int(segment.loadAddress) % page {
                issues.append(.misalignedFlashSegment(loadAddress: segment.loadAddress, fileOffset: offset))
            }
            offset += 8 + segment.data.count
        }
        return ImageValidation(issues: issues)
    }

    /// Resérialise en recalculant somme de contrôle et SHA-256.
    /// - Throws: `ImageError.invalidHeaderSetting` si la puce ne sait pas encoder les réglages flash.
    public func serialized() throws -> Data {
        var out = Data([0xE9, UInt8(clamping: segments.count), ChipImageTraits.code(for: flashMode),
                        try sizeFrequencyByte()])
        out.appendLE32(entryPoint)
        let header = extendedHeader
        let drive = header.spiPinDrive
        out.append(contentsOf: [header.wpPin, drive.clk & 0xF | drive.q << 4, drive.d & 0xF | drive.cs << 4,
                                drive.hd & 0xF | drive.wp << 4])
        out.appendLE16(header.chipID)
        out.append(header.legacyMinRevision)
        out.appendLE16(header.minRevision.encoded)
        out.appendLE16(header.maxRevision.encoded)
        out.append(contentsOf: [0, 0, 0, 0])
        out.append(header.hashAppended ? 1 : 0)
        for segment in segments {
            out.appendLE32(segment.loadAddress)
            out.appendLE32(UInt32(segment.data.count))
            out.append(segment.data)
        }
        out.append(Data(count: Self.checksumOffset(after: out.count) - out.count))
        out.append(checksum)
        if header.hashAppended { out.append(SHA256.hash(out)) }
        if let multiple = padToMultipleOf, multiple > 0, out.count % multiple != 0 {
            out.append(Data(repeating: 0xFF, count: multiple - out.count % multiple))
        }
        return out
    }

    /// XOR des données de tous les segments, valeur initiale 0xEF.
    var checksum: UInt8 {
        var value: UInt8 = 0xEF
        for segment in segments { for byte in segment.data { value ^= byte } }
        return value
    }

    private func sizeFrequencyByte() throws -> UInt8 {
        var size = rawSizeCode, frequency = rawFrequencyCode
        if let chip {
            let traits = ChipImageTraits(chip)
            if let flashSize {
                guard let code = traits.code(for: flashSize) else {
                    throw ImageError.invalidHeaderSetting("taille \(flashSize) non encodable pour \(chip)")
                }
                size = code
            }
            if let flashFrequency {
                guard let code = traits.code(for: flashFrequency) else {
                    throw ImageError.invalidHeaderSetting("fréquence \(flashFrequency) non encodable pour \(chip)")
                }
                frequency = code
            }
        }
        return size << 4 | frequency & 0xF
    }

    /// Position de l'octet de somme de contrôle : la fin des segments complétée par des zéros
    /// pour que l'octet suivant tombe sur un multiple de 16.
    static func checksumOffset(after offset: Int) -> Int {
        (offset + 16) / 16 * 16 - 1
    }

    private static func findAppDescription(in segments: [Segment]) -> AppDescription? {
        for segment in segments where segment.region?.isFlashMapped ?? true {
            if let description = AppDescription(data: segment.data) { return description }
        }
        return nil
    }
}

/// Structure `esp_app_desc_t` d'ESP-IDF, en tête du premier segment de données en flash.
public struct AppDescription: Hashable, Sendable {
    public static let magic: UInt32 = 0xABCD_5432

    public var secureVersion: UInt32
    public var version: String
    public var projectName: String
    public var compileTime: String
    public var compileDate: String
    public var idfVersion: String
    public var elfSHA256: Data
    public var minEfuseBlockRevision: ChipRevision
    public var maxEfuseBlockRevision: ChipRevision
    /// Taille de page MMU déclarée par l'application (ESP-IDF ≥ 5.4), en octets.
    public var mmuPageSize: Int?

    init?(data: Data) {
        let bytes = Data(data)
        guard bytes.count >= 176, bytes.readLE32(at: 0) == Self.magic else { return nil }
        secureVersion = bytes.readLE32(at: 4)
        version = Self.cString(bytes, 16, 32)
        projectName = Self.cString(bytes, 48, 32)
        compileTime = Self.cString(bytes, 80, 16)
        compileDate = Self.cString(bytes, 96, 16)
        idfVersion = Self.cString(bytes, 112, 32)
        elfSHA256 = bytes.subdata(in: 144..<176)
        if bytes.count >= 181 {
            minEfuseBlockRevision = ChipRevision(encoded: bytes.readLE16(at: 176))
            maxEfuseBlockRevision = ChipRevision(encoded: bytes.readLE16(at: 178))
            mmuPageSize = bytes[180] == 0 ? nil : 1 << Int(bytes[180])
        } else {
            minEfuseBlockRevision = ChipRevision(major: 0, minor: 0)
            maxEfuseBlockRevision = ChipRevision(encoded: 0xFFFF)
            mmuPageSize = nil
        }
    }

    static func cString(_ data: Data, _ offset: Int, _ length: Int) -> String {
        let field = data.subdata(in: offset..<min(data.count, offset + length))
        let end = field.firstIndex(of: 0) ?? field.endIndex
        return String(decoding: field[field.startIndex..<end], as: UTF8.self)
    }
}

/// Structure `esp_bootloader_desc_t` d'ESP-IDF, en tête du premier segment du bootloader.
public struct BootloaderDescription: Hashable, Sendable {
    public static let magic: UInt8 = 0x50

    public var secureVersion: UInt8
    public var version: UInt32
    public var idfVersion: String
    public var dateTime: String

    init?(data: Data) {
        let bytes = Data(data)
        guard bytes.count >= 64, bytes[0] == Self.magic else { return nil }
        secureVersion = bytes[3]
        version = bytes.readLE32(at: 4)
        idfVersion = AppDescription.cString(bytes, 8, 32)
        dateTime = AppDescription.cString(bytes, 40, 24)
    }
}
