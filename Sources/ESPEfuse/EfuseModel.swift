// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Field name. A chip's known fields are generated constants:
/// `EfuseFieldName.ESP32S3.spiBootCryptCnt`. A free-form name still works for extended tables.
public struct EfuseFieldName: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The name as espefuse prints it, for example "SPI_BOOT_CRYPT_CNT".
    public var rawValue: String
    /// A name; ESP-IDF names and espefuse aliases are both accepted.
    public init(_ rawValue: String) { self.rawValue = rawValue }
    /// A name from a string literal: `"DIS_USB_JTAG"`.
    public init(stringLiteral value: String) { self.rawValue = value }
    /// The name itself.
    public var description: String { rawValue }
}

/// Value of a field, typed after its ESP-IDF definition.
public enum EfuseValue: Hashable, Sendable {
    /// A one-bit field.
    case bool(Bool)
    /// An integer field of up to 64 bits.
    case uint(UInt64)
    /// A byte field (keys, digests, whole blocks), least significant byte first.
    case bytes(Data)
    /// A MAC address field.
    case mac(MACAddress)
    /// A `KEY_PURPOSE_n` field.
    case keyPurpose(KeyPurpose)
}

/// A decoded eFuse field.
public struct EfuseField: Hashable, Sendable {
    /// Name, as espefuse prints it.
    public var name: EfuseFieldName
    /// Display category, aligned with espefuse: "security", "flash", "MAC", "calibration"…
    public var category: String
    /// One-line description, aligned with espefuse.
    public var description: String
    /// Block holding the field.
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
    /// True if the field can no longer be read by software (its `RD_DIS` bit is set).
    public var isReadProtected: Bool
    /// True if the field can no longer be burned (its `WR_DIS` bit is set).
    public var isWriteProtected: Bool
    /// Type in espefuse's sense: `bool`, `uint:8`, `bytes:32`.
    public var type: String
}

/// Raw eFuse block.
public struct EfuseBlock: Hashable, Sendable {
    /// Block number, BLOCK0 first.
    public var index: Int
    /// Block name, for example "BLOCK_KEY0".
    public var name: String
    /// 32-bit words as read from the registers.
    public var words: [UInt32]
    /// True if the block reads back as zeros.
    public var isReadProtected: Bool
    /// True if the block can no longer be burned.
    public var isWriteProtected: Bool
}

/// Coding error reported by the controller.
public struct EfuseCodingError: Hashable, Sendable, CustomStringConvertible {
    /// What the controller reports.
    public enum Kind: Hashable, Sendable {
        /// BLOCK0: bits whose copies differ (`RD_REPEAT_ERR`), per word.
        case repeatMismatch(word: Int, bits: UInt32)
        /// Reed-Solomon RS(44,32): number of corrected bytes, and failure if uncorrectable.
        case reedSolomon(correctedBytes: Int, failed: Bool)
        /// ESP32, 3/4 coding: decoding warning.
        case threeQuarters(UInt32)
    }

    /// Block concerned.
    public var block: Int
    /// The error.
    public var kind: Kind

    /// A short explanation, in English.
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
    /// The chip the state belongs to.
    public var chip: ChipFamily
    /// Words of each block, in block order.
    public var blocks: [[UInt32]]
    /// Controller error registers, in the chip's own order.
    public var errorRegisters: [UInt32]
    /// ESP32: bit 31 of the APB_CTRL_DATE register, which tells revisions 2 and 3 apart.
    public var apbControlDate: UInt32?

    /// A state, for example rebuilt from an `espefuse dump`.
    public init(chip: ChipFamily, blocks: [[UInt32]], errorRegisters: [UInt32] = [], apbControlDate: UInt32? = nil) {
        self.chip = chip
        self.blocks = blocks
        self.errorRegisters = errorRegisters
        self.apbControlDate = apbControlDate
    }
}

/// eFuse errors.
public enum EfuseError: ESPKitError, Equatable {
    /// The plan cannot run; every problem is listed and nothing was burned.
    case planInvalid([EfusePlanIssue])
    /// Bits asked for did not read back as 1 after burning (and retrying).
    case verificationFailed(block: Int)
    /// After a hardware burn, bits the plan did not ask for read back as 1: ESPKit stops at once.
    case unexpectedBits(block: Int, word: Int, bits: UInt32)
    /// The token does not decode as an `EFSR:` state of the announced chip.
    case malformedToken
    /// Controller created from a token.
    case readOnly
    /// Chip whose table or registers ESPKit does not have.
    case unsupportedChip(ChipFamily)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .planInvalid(let issues): "Invalid burn plan: \(issues.map(\.description).joined(separator: "; "))"
        case .verificationFailed(let block): "BLOCK\(block) failed verification after burning"
        case .unexpectedBits(let block, let word, let bits):
            String(format: "BLOCK%d word %d: unexpected bits 0x%08x after burning; burning stopped", block, word, bits)
        case .malformedToken: "Unreadable eFuse token"
        case .readOnly: "Read-only controller"
        case .unsupportedChip(let chip): "\(chip) eFuses are not supported"
        }
    }
}
