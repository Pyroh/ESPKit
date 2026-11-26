// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSupport

/// Silicon revision, comparable ("v0.2" < "v1.0").
public struct ChipRevision: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Major revision (the "1" of v1.3).
    public var major: Int
    /// Minor revision (the "3" of v1.3).
    public var minor: Int

    /// A revision such as v1.3: `ChipRevision(major: 1, minor: 3)`.
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// `major * 100 + minor` encoding used by image headers.
    public init(encoded: UInt16) {
        self.init(major: Int(encoded) / 100, minor: Int(encoded) % 100)
    }

    /// `major * 100 + minor`, the encoding of image headers and eFuses.
    public var encoded: UInt16 { UInt16(clamping: major * 100 + minor) }

    /// For example "v1.3".
    public var description: String { "v\(major).\(minor)" }

    /// Orders revisions by major, then minor number.
    public static func < (lhs: ChipRevision, rhs: ChipRevision) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

/// 6-byte MAC address.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    /// Always 6 bytes (checked by the initializer).
    public let bytes: Data

    /// A MAC from its six bytes, most significant first; `nil` for any other length.
    public init?(bytes: Data) {
        guard bytes.count == 6 else { return nil }
        self.bytes = Data(bytes)
    }

    /// Parses "AA:BB:CC:DD:EE:FF" (`:` or `-` separators, case-insensitive).
    public init?(_ description: String) {
        let parts = description.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var bytes = Data()
        for part in parts {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.bytes = bytes
    }

    /// Upper-case, colon-separated: "24:0A:C4:12:34:56".
    public var description: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Purpose of an eFuse key block. Defined here because both `SecurityInfo` (ESPDevice) and `ESPEfuse` use it.
public enum KeyPurpose: Hashable, Sendable {
    /// Free data, readable by software (code 0).
    case user
    /// Reserved (code 1).
    case reserved
    /// XTS-AES-128 flash encryption key (code 4).
    case xtsAES128Key
    /// First half of an XTS-AES-256 flash encryption key (code 2).
    case xtsAES256Key1
    /// Second half of an XTS-AES-256 flash encryption key (code 3).
    case xtsAES256Key2
    /// HMAC key for every downstream use: JTAG and digital signature (code 5).
    case hmacDownAll
    /// HMAC key that re-enables a soft-disabled JTAG (code 6).
    case hmacDownJTAG
    /// HMAC key of the digital signature peripheral (code 7).
    case hmacDownDigitalSignature
    /// HMAC key readable by software through the HMAC peripheral (code 8).
    case hmacUp
    /// Digest of the first Secure Boot v2 public key (code 9).
    case secureBootDigest0
    /// Digest of the second Secure Boot v2 public key (code 10).
    case secureBootDigest1
    /// Digest of the third Secure Boot v2 public key (code 11).
    case secureBootDigest2
    /// Unlisted code, kept as is.
    case unknown(UInt8)

    /// Decodes a `KEY_PURPOSE_n` field value (codes shared by the ESP32-S2 and later chips).
    public init(rawCode: UInt8) {
        switch rawCode {
        case 0: self = .user
        case 1: self = .reserved
        case 2: self = .xtsAES256Key1
        case 3: self = .xtsAES256Key2
        case 4: self = .xtsAES128Key
        case 5: self = .hmacDownAll
        case 6: self = .hmacDownJTAG
        case 7: self = .hmacDownDigitalSignature
        case 8: self = .hmacUp
        case 9: self = .secureBootDigest0
        case 10: self = .secureBootDigest1
        case 11: self = .secureBootDigest2
        default: self = .unknown(rawCode)
        }
    }

    /// The `KEY_PURPOSE_n` code; ``unknown(_:)`` keeps its own.
    public var rawCode: UInt8 {
        switch self {
        case .user: 0
        case .reserved: 1
        case .xtsAES256Key1: 2
        case .xtsAES256Key2: 3
        case .xtsAES128Key: 4
        case .hmacDownAll: 5
        case .hmacDownJTAG: 6
        case .hmacDownDigitalSignature: 7
        case .hmacUp: 8
        case .secureBootDigest0: 9
        case .secureBootDigest1: 10
        case .secureBootDigest2: 11
        case .unknown(let code): code
        }
    }
}

/// MD5 digest, as computed by the chip.
public struct MD5Digest: Hashable, Sendable, CustomStringConvertible {
    /// 16 bytes.
    public let bytes: Data

    /// A digest from its 16 bytes; `nil` for any other length.
    public init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self.bytes = Data(bytes)
    }

    /// The MD5 of `data`, to compare with what the chip computes (`ESPDevice.flashMD5(at:count:)`).
    public init(hashing data: Data) {
        bytes = MD5.hash(data)
    }

    /// Lower-case hexadecimal, like `md5sum`.
    public var description: String { bytes.map { String(format: "%02x", $0) }.joined() }
}
