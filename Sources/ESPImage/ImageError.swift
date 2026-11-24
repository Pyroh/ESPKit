// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Image parsing and building errors.
public enum ImageError: ESPKitError, Equatable {
    /// Not a readable firmware image.
    case malformedImage(String)
    /// Not a readable 32-bit little-endian ELF.
    case malformedELF(String)
    /// Intel HEX record that does not parse, with its line number.
    case malformedIntelHex(line: Int, reason: String)
    /// Overlapping segments, impossible MMU alignment…
    case layout(String)
    /// No memory map or image format for this chip yet.
    case unsupportedChip(ChipFamily)
    /// Header setting that cannot be encoded for this chip.
    case invalidHeaderSetting(String)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .malformedImage(let reason): "Invalid image: \(reason)"
        case .malformedELF(let reason): "Invalid ELF: \(reason)"
        case .malformedIntelHex(let line, let reason): "Invalid Intel HEX, line \(line): \(reason)"
        case .layout(let reason): "Impossible layout: \(reason)"
        case .unsupportedChip(let chip): "Image format not supported for \(chip)"
        case .invalidHeaderSetting(let reason): "Invalid header setting: \(reason)"
        }
    }
}

/// Result of `validate()`: an empty list means the image is consistent.
public struct ImageValidation: Hashable, Sendable {
    /// One inconsistency.
    public enum Issue: Hashable, Sendable, CustomStringConvertible {
        /// The XOR checksum byte does not match the segments.
        case checksumMismatch(stored: UInt8, computed: UInt8)
        /// The appended SHA-256 does not match the image.
        case digestMismatch
        /// Two segments share addresses.
        case overlappingSegments(UInt32, UInt32)
        /// Flash-mapped segment whose file offset does not match its address
        /// modulo the MMU page.
        case misalignedFlashSegment(loadAddress: UInt32, fileOffset: Int)
        /// ESP8266 v2: the CRC32 does not match the file.
        case crcMismatch(stored: UInt32, computed: UInt32)

        /// A short explanation, in English.
        public var description: String {
            switch self {
            case .checksumMismatch(let stored, let computed):
                "checksum 0x\(String(stored, radix: 16)) instead of 0x\(String(computed, radix: 16))"
            case .digestMismatch: "invalid SHA-256 digest"
            case .overlappingSegments(let a, let b):
                "segments 0x\(String(a, radix: 16)) and 0x\(String(b, radix: 16)) overlap"
            case .misalignedFlashSegment(let address, let offset):
                "flash segment 0x\(String(address, radix: 16)) misaligned (offset 0x\(String(offset, radix: 16)))"
            case .crcMismatch(let stored, let computed):
                "CRC32 0x\(String(stored, radix: 16)) instead of 0x\(String(computed, radix: 16))"
            }
        }
    }

    /// Every problem found, in no particular order.
    public var issues: [Issue]
    /// True if nothing is wrong.
    public var isValid: Bool { issues.isEmpty }
}
