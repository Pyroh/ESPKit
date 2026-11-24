// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Secure Boot errors.
public enum SecureBootError: ESPKitError, Equatable {
    /// A key that cannot be read or used: wrong format, curve or size.
    case invalidKey(String)
    /// The scheme is not supported, by ESPKit (P-192) or by the chip.
    case schemeNotSupported(SecureBootV2.Scheme, chip: ChipFamily?)
    /// No signature verifies with the given key.
    case signatureInvalid
    /// At most 3 signature blocks.
    case tooManySignatures
    /// The image has no valid signature block, or nothing to sign with was given.
    case noSignatureBlock

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .invalidKey(let reason): "Invalid key: \(reason)"
        case .schemeNotSupported(let scheme, let chip):
            "Scheme \(scheme) not supported" + (chip.map { " on \($0)" } ?? "")
        case .signatureInvalid: "No signature verifies with this key"
        case .tooManySignatures: "At most three signature blocks"
        case .noSignatureBlock: "The image has no signature block"
        }
    }
}

/// Flash encryption errors.
public enum FlashEncryptionError: ESPKitError, Equatable {
    /// The key does not have the scheme's length (32 bytes, 64 for XTS-AES-256).
    case invalidKeyLength(Int, scheme: FlashEncryption.Scheme)
    /// Address or length that does not respect the scheme's alignment.
    case misaligned(address: UInt32, count: Int)
    /// Reserved for schemes ESPKit does not implement yet.
    case schemeNotSupported(FlashEncryption.Scheme)

    /// A readable description, in English.
    public var description: String {
        switch self {
        case .invalidKeyLength(let length, let scheme): "Invalid \(length)-byte key for \(scheme)"
        case .misaligned(let address, let count):
            "Address 0x\(String(address, radix: 16)) or length \(count) misaligned"
        case .schemeNotSupported(let scheme): "Scheme \(scheme) not supported yet"
        }
    }
}
