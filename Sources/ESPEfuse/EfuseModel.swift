// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Field name. A chip's known fields are generated constants:
/// `EfuseFieldName.ESP32S3.spiBootCryptCnt`. A free-form name still works for extended tables.
public struct EfuseFieldName: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

public enum EfuseValue: Hashable, Sendable {
    case bool(Bool)
    case uint(UInt64)
    case bytes(Data)
    case mac(MACAddress)
    case keyPurpose(KeyPurpose)
}

public struct EfuseField: Hashable, Sendable {
    public var name: EfuseFieldName
    /// Display category, aligned with espefuse: "security", "flash", "MAC", "calibration"…
    public var category: String
    public var description: String
    public var block: Int
    /// Bits within the block, in the order they form the value (least significant first).
    /// Empty for a field computed from other fields (`PKG_VERSION`…).
    public var bitRanges: [Range<Int>]
    /// First range of `bitRanges`: the field's position when it is contiguous.
    public var bitRange: Range<Int> { bitRanges.first ?? 0..<0 }
    /// Raw value.
    public var value: EfuseValue
    /// espefuse's presentation: named value (`"Disable"`), converted calibration (`-13.9`), MAC…
    public var displayValue: String
    public var isReadProtected: Bool
    public var isWriteProtected: Bool
    /// Type in espefuse's sense: `bool`, `uint:8`, `bytes:32`.
    public var type: String
}

/// Raw eFuse block.
public struct EfuseBlock: Hashable, Sendable {
    public var index: Int
    public var name: String
    /// 32-bit words as read from the registers.
    public var words: [UInt32]
    public var isReadProtected: Bool
    public var isWriteProtected: Bool
}

/// Coding error reported by the controller.
public struct EfuseCodingError: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// BLOCK0: bits whose copies differ (`RD_REPEAT_ERR`), per word.
        case repeatMismatch(word: Int, bits: UInt32)
        /// Reed-Solomon RS(44,32): number of corrected bytes, and failure if uncorrectable.
        case reedSolomon(correctedBytes: Int, failed: Bool)
        /// ESP32, 3/4 coding: decoding warning.
        case threeQuarters(UInt32)
    }

    public var block: Int
    public var kind: Kind

    public var description: String {
        switch kind {
        case .repeatMismatch(let word, let bits): "BLOCK\(block) word \(word): copies differ (0x\(String(bits, radix: 16)))"
        case .reedSolomon(let count, let failed):
            "BLOCK\(block): \(failed ? "uncorrectable RS error" : "\(count) byte(s) corrected by RS")"
        case .threeQuarters(let value): "BLOCK\(block): 3/4 coding error (0x\(String(value, radix: 16)))"
        }
    }
}

/// ADC and temperature sensor calibration, as `espefuse adc-info` shows it.
public struct ADCCalibration: Hashable, Sendable {
    /// Calibration block version (`BLK_VERSION_MAJOR`…), when the chip has one.
    public var blockVersion: Int?
    /// Converted values, by field name (mV, codes, °C).
    public var values: [String: Double]
}

/// Complete, serializable state: used by tests, `EfuseController(virtual:)` and tokens.
public struct EfuseSnapshot: Hashable, Sendable, Codable {
    public var chip: ChipFamily
    /// Words of each block, in block order.
    public var blocks: [[UInt32]]
    /// Controller error registers, in the chip's own order.
    public var errorRegisters: [UInt32]
    /// ESP32: bit 31 of the APB_CTRL_DATE register, which tells revisions 2 and 3 apart.
    public var apbControlDate: UInt32?

    public init(chip: ChipFamily, blocks: [[UInt32]], errorRegisters: [UInt32] = [], apbControlDate: UInt32? = nil) {
        self.chip = chip
        self.blocks = blocks
        self.errorRegisters = errorRegisters
        self.apbControlDate = apbControlDate
    }
}

/// eFuse errors.
public enum EfuseError: ESPKitError, Equatable {
    case planInvalid([EfusePlanIssue])
    case verificationFailed(block: Int)
    case malformedToken
    /// Controller created from a token.
    case readOnly
    /// Chip whose table or registers ESPKit does not have.
    case unsupportedChip(ChipFamily)

    public var description: String {
        switch self {
        case .planInvalid(let issues): "Invalid burn plan: \(issues.map(\.description).joined(separator: "; "))"
        case .verificationFailed(let block): "BLOCK\(block) failed verification after burning"
        case .malformedToken: "Unreadable eFuse token"
        case .readOnly: "Read-only controller"
        case .unsupportedChip(let chip): "\(chip) eFuses are not supported"
        }
    }
}
