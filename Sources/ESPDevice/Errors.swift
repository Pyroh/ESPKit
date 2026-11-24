// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Failures to establish or use the session.
public enum ConnectionError: ESPKitError, Equatable {
    /// No answer to SYNC after every attempt.
    case noResponse(attempts: Int)
    case chipMismatch(expected: ChipFamily, detected: ChipFamily)
    case unknownChip(magic: UInt32?, chipID: UInt32?)
    /// No port matches the `connectFirstAvailable` filter.
    case noMatchingPort
    /// Operation on an `ESPDevice` after `disconnect`, `loadRAMAndRun` or `runFlashApplication`.
    case disconnected

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
    case timeout(opcode: UInt8?, after: Duration)
    case invalidResponse(String)
    /// The ROM or the stub answered with a failure.
    case deviceError(opcode: UInt8, code: DeviceErrorCode)

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
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let invalidMessage = DeviceErrorCode(rawValue: 0x05)
    public static let failedToAct = DeviceErrorCode(rawValue: 0x06)
    public static let invalidCRC = DeviceErrorCode(rawValue: 0x07)
    public static let flashWriteError = DeviceErrorCode(rawValue: 0x08)
    public static let flashReadError = DeviceErrorCode(rawValue: 0x09)
    public static let flashReadLengthError = DeviceErrorCode(rawValue: 0x0A)
    public static let deflateError = DeviceErrorCode(rawValue: 0x0B)

    // Stub v2 codes (high byte of its response code).
    public static let badDataLength = DeviceErrorCode(rawValue: 0xC0)
    public static let badDataChecksum = DeviceErrorCode(rawValue: 0xC1)
    public static let badBlockSize = DeviceErrorCode(rawValue: 0xC2)
    public static let invalidCommand = DeviceErrorCode(rawValue: 0xC3)
    public static let failedSPIOperation = DeviceErrorCode(rawValue: 0xC4)
    public static let failedSPIUnlock = DeviceErrorCode(rawValue: 0xC5)
    public static let notInFlashMode = DeviceErrorCode(rawValue: 0xC6)
    public static let inflateError = DeviceErrorCode(rawValue: 0xC7)
    public static let notEnoughData = DeviceErrorCode(rawValue: 0xC8)
    public static let tooMuchData = DeviceErrorCode(rawValue: 0xC9)
    public static let commandNotImplemented = DeviceErrorCode(rawValue: 0xFF)

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
    case unsupported(feature: String, chip: ChipFamily, state: ESPDevice.State)
    case unavailableInSecureDownloadMode(operation: String)
    case invalidArgument(String)
    /// Can be overridden with `force`.
    case securityRestriction(String)
    /// Can be overridden with `force`.
    case imageIncompatible(String)

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
    case md5Mismatch(address: UInt32, expected: MD5Digest, actual: MD5Digest)
    /// RDID returns 0x000000, 0xFFFFFF or 0xFFFF3F: no flash answers on the SPI bus.
    case notDetected(jedecID: UInt32)

    public var description: String {
        switch self {
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
    case chipMismatch(stub: ChipFamily, device: ChipFamily)
    /// Segments that overlap each other or the BSS.
    case overlapping(String)
    /// No bundled stub for this chip.
    case noBundledStub(ChipFamily)
    /// No `OHAI` after launch.
    case failedToStart(StubImage.Version)

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
