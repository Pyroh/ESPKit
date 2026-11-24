// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Erreurs de Secure Boot.
public enum SecureBootError: ESPKitError, Equatable {
    case invalidKey(String)
    case schemeNotSupported(SecureBootV2.Scheme, chip: ChipFamily?)
    case signatureInvalid
    /// 3 blocs de signature au maximum.
    case tooManySignatures
    case noSignatureBlock

    public var description: String {
        switch self {
        case .invalidKey(let reason): "Clé invalide : \(reason)"
        case .schemeNotSupported(let scheme, let chip):
            "Schéma \(scheme) non pris en charge" + (chip.map { " sur \($0)" } ?? "")
        case .signatureInvalid: "Aucune signature ne vérifie avec cette clé"
        case .tooManySignatures: "Trois blocs de signature au maximum"
        case .noSignatureBlock: "L'image ne porte pas de bloc de signature"
        }
    }
}

/// Erreurs de chiffrement flash.
public enum FlashEncryptionError: ESPKitError, Equatable {
    case invalidKeyLength(Int, scheme: FlashEncryption.Scheme)
    /// Adresse ou longueur qui ne respecte pas l'alignement du schéma.
    case misaligned(address: UInt32, count: Int)
    case schemeNotSupported(FlashEncryption.Scheme)

    public var description: String {
        switch self {
        case .invalidKeyLength(let length, let scheme): "Clé de \(length) octets invalide pour \(scheme)"
        case .misaligned(let address, let count):
            "Adresse 0x\(String(address, radix: 16)) ou longueur \(count) mal alignée"
        case .schemeNotSupported(let scheme): "Schéma \(scheme) pas encore pris en charge"
        }
    }
}
