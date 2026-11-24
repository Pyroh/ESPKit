// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport
import ESPTargets

/// ESP8266 image: no extended header and no SHA-256.
/// - v1: 0xE9 header and RAM segments; the flash code (IROM) is a separate raw file.
/// - v2: 0xEA header followed by the IROM segment, then a 0xE9 header and the RAM segments,
///   and finally a CRC32 of the whole file.
public struct ESP8266Image: Hashable, Sendable {
    /// ESP8266 image layout.
    public enum Format: Hashable, Sendable {
        /// Two files: header and RAM segments, then the raw IROM.
        case v1
        /// One file with the IROM segment, the RAM segments and a CRC32 (OTA builds).
        case v2
    }

    /// Layout of this image.
    public var format: Format
    /// Entry point the ROM jumps to.
    public var entryPoint: UInt32
    /// SPI mode from the header.
    public var flashMode: FlashMode
    /// Flash frequency from the header; `nil` for an unknown code.
    public var flashFrequency: FlashFrequency?
    /// Flash size from the header; `nil` for an unknown code.
    public var flashSize: FlashSize?
    /// RAM segments, in file order.
    public var segments: [FirmwareImage.Segment]
    /// v2 only: the flash code, stored at the start of the file.
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

    /// Parses a v1 or v2 ESP8266 image without checking it: see ``validate()``.
    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data) throws {
        let bytes = Data(data)
        let traits = ChipImageTraits(.esp8266)
        guard bytes.count >= 8 else { throw ImageError.malformedImage("fewer than 8 bytes") }
        var offset = 0
        var irom: FirmwareImage.Segment?
        switch bytes[0] {
        case 0xEA:
            format = .v2
            guard bytes.count >= 16 else { throw ImageError.malformedImage("v2 header truncated") }
            let length = Int(bytes.readLE32(at: 12))
            guard 16 + length <= bytes.count else { throw ImageError.malformedImage("IROM segment truncated") }
            irom = FirmwareImage.Segment(loadAddress: bytes.readLE32(at: 8), data: bytes.subdata(in: 16..<16 + length),
                                         region: .irom)
            offset = 16 + length
        case 0xE9:
            format = .v1
        default:
            throw ImageError.malformedImage("unknown ESP8266 magic 0x\(String(bytes[0], radix: 16))")
        }
        guard offset + 8 <= bytes.count, bytes[offset] == 0xE9 else { throw ImageError.malformedImage("missing 0xE9 header") }
        guard let mode = ChipImageTraits.mode(forCode: bytes[offset + 2]) else {
            throw ImageError.malformedImage("unknown flash mode \(bytes[offset + 2])")
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
            guard offset + 8 <= bytes.count else { throw ImageError.malformedImage("segment \(index) header truncated") }
            let address = bytes.readLE32(at: offset)
            let length = Int(bytes.readLE32(at: offset + 4))
            guard offset + 8 + length <= bytes.count else { throw ImageError.malformedImage("segment \(index) truncated") }
            segments.append(.init(loadAddress: address, data: bytes.subdata(in: offset + 8..<offset + 8 + length),
                                  region: traits.region(of: address)))
            offset += 8 + length
        }
        self.segments = segments
        iromSegment = irom
        let checksumOffset = FirmwareImage.checksumOffset(after: offset)
        guard checksumOffset < bytes.count else { throw ImageError.malformedImage("missing checksum") }
        var parsed = Parsed(storedChecksum: bytes[checksumOffset])
        if format == .v2, checksumOffset + 5 <= bytes.count {
            parsed.storedCRC = bytes.readLE32(at: checksumOffset + 1)
            parsed.computedCRC = Self.crc(bytes.prefix(checksumOffset + 1))
        }
        self.parsed = parsed
    }

    /// Checks the checksum and, for v2, the CRC32 against the parsed bytes.
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

    /// For v1, only the "0x00000.bin" file: the IROM code is a separate raw file.
    public func serialized() throws -> Data {
        let traits = ChipImageTraits(.esp8266)
        var size = rawSizeCode, frequency = rawFrequencyCode
        if let flashSize {
            guard let code = traits.code(for: flashSize) else { throw ImageError.invalidHeaderSetting("size \(flashSize)") }
            size = code
        }
        if let flashFrequency {
            guard let code = traits.code(for: flashFrequency) else { throw ImageError.invalidHeaderSetting("frequency \(flashFrequency)") }
            frequency = code
        }
        let flags = [ChipImageTraits.code(for: flashMode), size << 4 | frequency]
        var out = Data()
        if format == .v2 {
            out.append(contentsOf: [0xEA, 4] + flags)
            out.appendLE32(entryPoint)
            if let irom = iromSegment {
                // The IROM segment is stored at address 0 and ends on a 16-byte boundary.
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

    /// CRC used by recent ESP8266 SDK bootloaders: standard CRC-32, complemented if its top bit
    /// is set, incremented otherwise.
    static func crc(_ data: Data) -> UInt32 {
        let crc = Zlib.crc32(data)
        return crc & 0x8000_0000 != 0 ? crc ^ 0xFFFF_FFFF : crc &+ 1
    }
}

/// Parses a binary without knowing its format in advance (the equivalent of `image-info`).
public enum AnyFirmwareImage: Hashable, Sendable {
    /// An ESP32-family image (0xE9 header with an extended header).
    case esp32Family(FirmwareImage)
    /// An ESP8266 image (v1 or v2).
    case esp8266(ESP8266Image)

    /// `chip` resolves the ambiguity when the header is not enough (the ESP8266 writes no chip ID).
    /// - Throws: `ImageError.malformedImage`.
    public init(parsing data: Data, chip: ChipFamily? = nil) throws {
        guard let first = data.first else { throw ImageError.malformedImage("empty file") }
        if first == 0xEA || chip == .esp8266 {
            self = .esp8266(try ESP8266Image(parsing: data))
            return
        }
        if chip != nil {
            self = .esp32Family(try FirmwareImage(parsing: data))
            return
        }
        // Without a hint: the extended header of ESP32 chips holds a known ID and 4 zero reserved bytes.
        let bytes = Data(data)
        if bytes.count >= 24, ChipFamily(imageChipID: bytes.readLE16(at: 12)) != nil,
           bytes[19..<23].allSatisfy({ $0 == 0 }), bytes[23] <= 1 {
            self = .esp32Family(try FirmwareImage(parsing: bytes))
        } else {
            self = .esp8266(try ESP8266Image(parsing: bytes))
        }
    }
}
