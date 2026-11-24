// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Secure Boot errors.
public enum SecureBootError: ESPKitError, Equatable {
    case invalidKey(String)
    case schemeNotSupported(SecureBootV2.Scheme, chip: ChipFamily?)
    case signatureInvalid
    /// At most 3 signature blocks.
    case tooManySignatures
    case noSignatureBlock

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
    case invalidKeyLength(Int, scheme: FlashEncryption.Scheme)
    /// Address or length that does not respect the scheme's alignment.
    case misaligned(address: UInt32, count: Int)
    case schemeNotSupported(FlashEncryption.Scheme)

    public var description: String {
        switch self {
        case .invalidKeyLength(let length, let scheme): "Invalid \(length)-byte key for \(scheme)"
        case .misaligned(let address, let count):
            "Address 0x\(String(address, radix: 16)) or length \(count) misaligned"
        case .schemeNotSupported(let scheme): "Scheme \(scheme) not supported yet"
        }
    }
}
