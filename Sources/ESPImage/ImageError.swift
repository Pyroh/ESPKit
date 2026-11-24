// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Image parsing and building errors.
public enum ImageError: ESPKitError, Equatable {
    case malformedImage(String)
    case malformedELF(String)
    case malformedIntelHex(line: Int, reason: String)
    /// Overlapping segments, impossible MMU alignment…
    case layout(String)
    case unsupportedChip(ChipFamily)
    /// Header setting that cannot be encoded for this chip.
    case invalidHeaderSetting(String)

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
    public enum Issue: Hashable, Sendable, CustomStringConvertible {
        case checksumMismatch(stored: UInt8, computed: UInt8)
        case digestMismatch
        case overlappingSegments(UInt32, UInt32)
        /// Flash-mapped segment whose file offset does not match its address
        /// modulo the MMU page.
        case misalignedFlashSegment(loadAddress: UInt32, fileOffset: Int)
        case crcMismatch(stored: UInt32, computed: UInt32)

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

    public var issues: [Issue]
    public var isValid: Bool { issues.isEmpty }
}
