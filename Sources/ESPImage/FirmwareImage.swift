// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// Output drive strength of the SPI flash pins (0 to 15 per pin), in the extended header.
public struct SPIPinDrive: Hashable, Sendable {
    /// Clock pin.
    public var clk: UInt8 = 0
    /// Q (MISO) pin.
    public var q: UInt8 = 0
    /// D (MOSI) pin.
    public var d: UInt8 = 0
    /// Chip-select pin.
    public var cs: UInt8 = 0
    /// HD (hold) pin.
    public var hd: UInt8 = 0
    /// WP (write-protect) pin.
    public var wp: UInt8 = 0

    /// Drive strengths, 0 (the default) to 15.
    public init(clk: UInt8 = 0, q: UInt8 = 0, d: UInt8 = 0, cs: UInt8 = 0, hd: UInt8 = 0, wp: UInt8 = 0) {
        self.clk = clk; self.q = q; self.d = d; self.cs = cs; self.hd = hd; self.wp = wp
    }
}

/// Application or bootloader image in the ESP32 format (0xE9 header + extended header).
public struct FirmwareImage: Hashable, Sendable {
    /// Deduced from the extended header; `nil` if the chip ID is unknown.
    public var chip: ChipFamily?
    /// Entry point the bootloader (or the ROM) jumps to.
    public var entryPoint: UInt32
    /// SPI mode from the header.
    public var flashMode: FlashMode
    /// `nil` if the header code is unknown for the chip.
    public var flashFrequency: FlashFrequency?
    /// `nil` if the header code is unknown for the chip.
    public var flashSize: FlashSize?
    /// Segments in file order, the ones the header counts.
    public var segments: [Segment]
    /// Segments after the checksum, which the header does not count and the ROM does not load
    /// (`ImageOptions.ramOnlyHeader`: the flash-mapped segments, with their padding). Not
    /// covered by the checksum. Parsing does not recover them.
    public var hiddenSegments: [Segment] = []
    /// The 16-byte header that follows the common one: chip, revisions, SHA-256 flag.
    public var extendedHeader: ExtendedHeader
    /// ESP-IDF application description, found in the first flash data segment.
    public var appDescription: AppDescription?
    /// ESP-IDF bootloader description, found at the start of the first segment.
    public var bootloaderDescription: BootloaderDescription?
    /// Final 0xFF padding up to a multiple of this size (`--pad-to-size`).
    public var padToMultipleOf: Int?

    /// A segment: bytes and where the loader copies or maps them.
    public struct Segment: Hashable, Sendable {
        /// Address in the chip's memory map.
        public var loadAddress: UInt32
        /// Contents.
        public var data: Data
        /// Region that `loadAddress` falls in, when the chip's memory map is known.
        public var region: MemoryRegion?

        /// A segment; `region` is informational (the image builder fills it in).
        public init(loadAddress: UInt32, data: Data, region: MemoryRegion? = nil) {
            self.loadAddress = loadAddress
            self.data = data
            self.region = region
        }
    }

    /// Extended header of ESP32-family images.
    public struct ExtendedHeader: Hashable, Sendable {
        /// 0xEE: WP pin disabled.
        public var wpPin: UInt8 = 0xEE
        /// Drive strength of the flash pins.
        public var spiPinDrive = SPIPinDrive()
        /// Raw chip ID (`ChipFamily.imageChipID`).
        public var chipID: UInt16
        /// Oldest chip revision allowed to run the image.
        public var minRevision: ChipRevision
        /// Newest chip revision allowed to run the image (v655.35 = no limit).
        public var maxRevision: ChipRevision
        /// True if a SHA-256 of the image follows the checksum.
        public var hashAppended: Bool
        /// Legacy one-byte minimum revision field (major only).
        public var legacyMinRevision: UInt8 = 0

        /// A header for `chipID`, with no revision limit and a SHA-256 by default.
        public init(chipID: UInt16, minRevision: ChipRevision = .init(major: 0, minor: 0),
                    maxRevision: ChipRevision = .init(encoded: 0xFFFF), hashAppended: Bool = true) {
            self.chipID = chipID
            self.minRevision = minRevision
            self.maxRevision = maxRevision
            self.hashAppended = hashAppended
        }
    }

    /// Header codes kept when the chip or the code does not decode.
    var rawSizeCode: UInt8 = 0
    var rawFrequencyCode: UInt8 = 0
    /// What was read from the file, for `validate()`.
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

    /// Parses without checking the checksums: see `validate()`.
    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        guard bytes.count >= 24 else { throw ImageError.malformedImage("fewer than 24 bytes") }
        guard bytes[0] == 0xE9 else { throw ImageError.malformedImage("magic 0x\(String(bytes[0], radix: 16)) instead of 0xE9") }
        guard let mode = ChipImageTraits.mode(forCode: bytes[2]) else {
            throw ImageError.malformedImage("unknown flash mode \(bytes[2])")
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
            guard offset + 8 <= bytes.count else { throw ImageError.malformedImage("segment \(index) header truncated") }
            let address = bytes.readLE32(at: offset)
            let length = Int(bytes.readLE32(at: offset + 4))
            guard offset + 8 + length <= bytes.count else { throw ImageError.malformedImage("segment \(index) truncated") }
            segments.append(Segment(loadAddress: address, data: bytes.subdata(in: offset + 8..<offset + 8 + length),
                                    region: traits?.region(of: address)))
            offset += 8 + length
        }
        let checksumOffset = Self.checksumOffset(after: offset)
        guard checksumOffset < bytes.count else { throw ImageError.malformedImage("missing checksum") }

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

    /// Checks: checksum, SHA-256, overlaps, MMU alignment of flash segments.
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

    /// Serializes again, recomputing the checksum and the SHA-256.
    /// - Throws: `ImageError.invalidHeaderSetting` if the chip cannot encode the flash settings.
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
        for segment in hiddenSegments {
            out.appendLE32(segment.loadAddress)
            out.appendLE32(UInt32(segment.data.count))
            out.append(segment.data)
        }
        if header.hashAppended { out.append(SHA256.hash(out)) }
        if let multiple = padToMultipleOf, multiple > 0, out.count % multiple != 0 {
            out.append(Data(repeating: 0xFF, count: multiple - out.count % multiple))
        }
        return out
    }

    /// XOR of every segment's data, seeded with 0xEF.
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
                    throw ImageError.invalidHeaderSetting("size \(flashSize) cannot be encoded for \(chip)")
                }
                size = code
            }
            if let flashFrequency {
                guard let code = traits.code(for: flashFrequency) else {
                    throw ImageError.invalidHeaderSetting("frequency \(flashFrequency) cannot be encoded for \(chip)")
                }
                frequency = code
            }
        }
        return size << 4 | frequency & 0xF
    }

    /// Position of the checksum byte: the end of the segments, padded with zeros
    /// so that the next byte falls on a multiple of 16.
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

/// ESP-IDF's `esp_app_desc_t` structure, at the start of the first flash data segment.
public struct AppDescription: Hashable, Sendable {
    /// `ESP_APP_DESC_MAGIC_WORD`.
    public static let magic: UInt32 = 0xABCD_5432

    /// Anti-rollback version (`CONFIG_BOOTLOADER_APP_SECURE_VERSION`).
    public var secureVersion: UInt32
    /// Application version string (`PROJECT_VER`).
    public var version: String
    /// Project name.
    public var projectName: String
    /// Build time (`__TIME__`).
    public var compileTime: String
    /// Build date (`__DATE__`).
    public var compileDate: String
    /// ESP-IDF version the application was built with.
    public var idfVersion: String
    /// SHA-256 of the ELF, written by `elf2image` (32 bytes).
    public var elfSHA256: Data
    /// Oldest eFuse block revision the application supports.
    public var minEfuseBlockRevision: ChipRevision
    /// Newest eFuse block revision the application supports.
    public var maxEfuseBlockRevision: ChipRevision
    /// MMU page size declared by the application (ESP-IDF ≥ 5.4), in bytes.
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

/// ESP-IDF's `esp_bootloader_desc_t` structure, at the start of the bootloader's first segment.
public struct BootloaderDescription: Hashable, Sendable {
    /// `ESP_BOOTLOADER_DESC_MAGIC_BYTE`.
    public static let magic: UInt8 = 0x50

    /// Anti-rollback version of the bootloader.
    public var secureVersion: UInt8
    /// Bootloader version (`CONFIG_BOOTLOADER_PROJECT_VER`).
    public var version: UInt32
    /// ESP-IDF version the bootloader was built with.
    public var idfVersion: String
    /// Build date and time.
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
