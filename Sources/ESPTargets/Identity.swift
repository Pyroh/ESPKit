// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Révision de silicium, comparable (« v0.2 » < « v1.0 »).
public struct ChipRevision: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Encodage `major * 100 + minor` des en-têtes d'image.
    public init(encoded: UInt16) {
        self.init(major: Int(encoded) / 100, minor: Int(encoded) % 100)
    }

    public var encoded: UInt16 { UInt16(clamping: major * 100 + minor) }

    public var description: String { "v\(major).\(minor)" }

    public static func < (lhs: ChipRevision, rhs: ChipRevision) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

/// Adresse MAC sur 6 octets.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    /// Toujours 6 octets (vérifié à l'init).
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 6 else { return nil }
        self.bytes = Data(bytes)
    }

    /// Lit « AA:BB:CC:DD:EE:FF » (séparateurs `:` ou `-`, casse indifférente).
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

    public var description: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Usage d'un bloc de clé eFuse. Défini ici car `SecurityInfo` (ESPDevice) et `ESPEfuse` l'utilisent tous deux.
public enum KeyPurpose: Hashable, Sendable {
    case user, reserved
    case xtsAES128Key, xtsAES256Key1, xtsAES256Key2
    case hmacDownAll, hmacDownJTAG, hmacDownDigitalSignature, hmacUp
    case secureBootDigest0, secureBootDigest1, secureBootDigest2
    /// Code non répertorié, conservé tel quel.
    case unknown(UInt8)

    /// Décode la valeur du champ `KEY_PURPOSE_n` (codes communs aux puces ESP32-S2 et suivantes).
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

/// Empreinte MD5, comme la calcule la puce.
public struct MD5Digest: Hashable, Sendable, CustomStringConvertible {
    /// 16 octets.
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self.bytes = Data(bytes)
    }

    public var description: String { bytes.map { String(format: "%02x", $0) }.joined() }
}
