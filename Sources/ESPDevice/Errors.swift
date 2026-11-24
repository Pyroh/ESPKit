// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Failures to establish or use the session.
public enum ConnectionError: ESPKitError, Equatable {
    /// No answer to SYNC after every attempt.
    case noResponse(attempts: Int)
    /// `ConnectOptions.expectedChip` differs from the chip that answered.
    case chipMismatch(expected: ChipFamily, detected: ChipFamily)
    /// Neither the magic value nor the chip ID matches a known family.
    case unknownChip(magic: UInt32?, chipID: UInt32?)
    /// No port matches the `connectFirstAvailable` filter.
    case noMatchingPort
    /// Operation on an `ESPDevice` after `disconnect`, `loadRAMAndRun` or `runFlashApplication`.
    case disconnected

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .noResponse(let attempts):
            "The chip does not answer (\(attempts) attempt(s)). Check the cable, the port and the boot mode."
        case .chipMismatch(let expected, let detected):
            "Unexpected chip: \(expected) requested, \(detected) detected"
        case .unknownChip(let magic, let chipID):
            "Unknown chip (magic \(magic.map(hex) ?? "—"), chip ID \(chipID.map(String.init) ?? "—"))"
        case .noMatchingPort:
            "No serial port matches the filter"
        case .disconnected:
            "The session is closed"
        }
    }
}

/// Errors exchanging with the ROM or the stub.
public enum ProtocolError: ESPKitError, Equatable {
    /// No response to the command `opcode` (`nil` for a raw read) within `after`.
    case timeout(opcode: UInt8?, after: Duration)
    /// A response that does not fit the protocol (length, opcode, digest…).
    case invalidResponse(String)
    /// The ROM or the stub answered with a failure.
    case deviceError(opcode: UInt8, code: DeviceErrorCode)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .timeout(let opcode, let after):
            "No response to command \(opcode.map(hex) ?? "?") after \(after)"
        case .invalidResponse(let reason):
            "Inconsistent response: \(reason)"
        case .deviceError(let opcode, let code):
            "The chip refused command \(hex(opcode)): \(code)"
        }
    }
}

/// Failure codes of the ROM or the stub. An unknown code is kept as is.
public struct DeviceErrorCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// The code: the ROM's error byte, or the high byte of the stub's 16-bit code.
    public var rawValue: UInt8
    /// Wraps a code, known or not.
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// ROM 0x05: malformed command.
    public static let invalidMessage = DeviceErrorCode(rawValue: 0x05)
    /// ROM 0x06: the command failed.
    public static let failedToAct = DeviceErrorCode(rawValue: 0x06)
    /// ROM 0x07: data checksum mismatch.
    public static let invalidCRC = DeviceErrorCode(rawValue: 0x07)
    /// ROM 0x08: flash write failed.
    public static let flashWriteError = DeviceErrorCode(rawValue: 0x08)
    /// ROM 0x09: flash read failed.
    public static let flashReadError = DeviceErrorCode(rawValue: 0x09)
    /// ROM 0x0A: invalid flash read length.
    public static let flashReadLengthError = DeviceErrorCode(rawValue: 0x0A)
    /// ROM 0x0B: compressed data could not be inflated.
    public static let deflateError = DeviceErrorCode(rawValue: 0x0B)

    // Stub v2 codes (high byte of its response code).
    /// Stub 0xC0: payload length does not fit the command.
    public static let badDataLength = DeviceErrorCode(rawValue: 0xC0)
    /// Stub 0xC1: data checksum mismatch.
    public static let badDataChecksum = DeviceErrorCode(rawValue: 0xC1)
    /// Stub 0xC2: unsupported block size.
    public static let badBlockSize = DeviceErrorCode(rawValue: 0xC2)
    /// Stub 0xC3: unknown command.
    public static let invalidCommand = DeviceErrorCode(rawValue: 0xC3)
    /// Stub 0xC4: an SPI flash operation failed.
    public static let failedSPIOperation = DeviceErrorCode(rawValue: 0xC4)
    /// Stub 0xC5: the flash could not be unlocked for writing.
    public static let failedSPIUnlock = DeviceErrorCode(rawValue: 0xC5)
    /// Stub 0xC6: a data or end command came without a begin.
    public static let notInFlashMode = DeviceErrorCode(rawValue: 0xC6)
    /// Stub 0xC7: compressed data could not be inflated.
    public static let inflateError = DeviceErrorCode(rawValue: 0xC7)
    /// Stub 0xC8: fewer bytes than announced.
    public static let notEnoughData = DeviceErrorCode(rawValue: 0xC8)
    /// Stub 0xC9: more bytes than announced.
    public static let tooMuchData = DeviceErrorCode(rawValue: 0xC9)
    /// Stub 0xFF: the command exists but is not implemented.
    public static let commandNotImplemented = DeviceErrorCode(rawValue: 0xFF)

    /// A readable description, in English.
    public var description: String {
        let name: String? = switch rawValue {
        case 0x05: "invalid message"
        case 0x06: "failed to act"
        case 0x07: "invalid CRC"
        case 0x08: "flash write error"
        case 0x09: "flash read error"
        case 0x0A: "invalid flash read length"
        case 0x0B: "deflate error"
        case 0xC0: "bad data length"
        case 0xC1: "bad data checksum"
        case 0xC2: "bad block size"
        case 0xC3: "invalid command"
        case 0xC4: "failed SPI operation"
        case 0xC5: "failed SPI unlock"
        case 0xC6: "not in flash mode"
        case 0xC7: "inflate error"
        case 0xC8: "not enough data"
        case 0xC9: "too much data"
        case 0xCA: "NAND program failed"
        case 0xCB: "NAND erase failed"
        case 0xFF: "command not implemented"
        default: nil
        }
        return name.map { "\($0) (\(hex(rawValue)))" } ?? "code \(hex(rawValue))"
    }
}

/// API misuse, or an operation impossible in the chip's current state.
public enum UsageError: ESPKitError, Equatable {
    /// The feature does not exist on this chip or in this state (for example "Full erase" under ROM).
    case unsupported(feature: String, chip: ChipFamily, state: ESPDevice.State)
    /// The chip is in Secure Download Mode; nothing was sent.
    case unavailableInSecureDownloadMode(operation: String)
    /// An argument out of range: misaligned address, overlapping regions, too much data…
    case invalidArgument(String)
    /// Can be overridden with `force`.
    case securityRestriction(String)
    /// Can be overridden with `force`.
    case imageIncompatible(String)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .unsupported(let feature, let chip, let state):
            "\(feature) is not available on \(chip) (\(state))"
        case .unavailableInSecureDownloadMode(let operation):
            "\(operation) is impossible in Secure Download Mode"
        case .invalidArgument(let reason):
            "Invalid argument: \(reason)"
        case .securityRestriction(let reason):
            "Refused for security: \(reason) (override with `force`)"
        case .imageIncompatible(let reason):
            "Incompatible image: \(reason) (override with `force`)"
        }
    }
}

/// Flash-specific errors.
public enum FlashError: ESPKitError, Equatable {
    /// The chip's MD5 of the region at `address` differs from the data's.
    case md5Mismatch(address: UInt32, expected: MD5Digest, actual: MD5Digest)
    /// RDID returns 0x000000, 0xFFFFFF or 0xFFFF3F: no flash answers on the SPI bus.
    case notDetected(jedecID: UInt32)
    /// The status register reads back another value after `writeFlashStatus`.
    case statusMismatch(expected: UInt32, actual: UInt32)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .statusMismatch(let expected, let actual):
            "Flash status reads \(hex(actual)) after writing \(hex(expected))"

        case .md5Mismatch(let address, let expected, let actual):
            "MD5 mismatch at \(hex(address)): expected \(expected), read \(actual)"
        case .notDetected(let id):
            "No flash answers (JEDEC ID \(hex(id))). Check the SPI wiring."
        }
    }
}

/// Stub-related errors.
public enum StubError: ESPKitError, Equatable {
    /// Unreadable JSON, empty segment, misaligned address.
    case malformed(String)
    /// The stub is built for another chip than the one connected.
    case chipMismatch(stub: ChipFamily, device: ChipFamily)
    /// Segments that overlap each other or the BSS.
    case overlapping(String)
    /// No bundled stub for this chip.
    case noBundledStub(ChipFamily)
    /// No `OHAI` after launch.
    case failedToStart(StubImage.Version)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .malformed(let reason): "Invalid stub image: \(reason)"
        case .chipMismatch(let stub, let device): "Stub built for \(stub), connected chip: \(device)"
        case .overlapping(let reason): "Inconsistent stub segments: \(reason)"
        case .noBundledStub(let chip): "No bundled stub for \(chip)"
        case .failedToStart(let version): "Stub \(version) did not start (no OHAI)"
        }
    }
}

func hex<T: FixedWidthInteger>(_ value: T) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}
