// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Nom de champ. Les champs connus d'une puce sont des constantes générées :
/// `EfuseFieldName.ESP32S3.spiBootCryptCnt`. Un nom libre reste possible pour les tables étendues.
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
    /// Catégorie d'affichage, alignée sur espefuse : "security", "flash", "MAC", "calibration"…
    public var category: String
    public var description: String
    public var block: Int
    /// Bits dans le bloc, dans l'ordre où ils forment la valeur (poids faible d'abord).
    /// Vide pour un champ calculé à partir d'autres champs (`PKG_VERSION`…).
    public var bitRanges: [Range<Int>]
    /// Premier intervalle de `bitRanges` : la position du champ quand il est d'un seul tenant.
    public var bitRange: Range<Int> { bitRanges.first ?? 0..<0 }
    /// Valeur brute.
    public var value: EfuseValue
    /// Présentation d'espefuse : valeur nommée (`"Disable"`), calibration convertie (`-13.9`), MAC…
    public var displayValue: String
    public var isReadProtected: Bool
    public var isWriteProtected: Bool
    /// Type au sens d'espefuse : `bool`, `uint:8`, `bytes:32`.
    public var type: String
}

/// Bloc d'eFuses brut.
public struct EfuseBlock: Hashable, Sendable {
    public var index: Int
    public var name: String
    /// Mots de 32 bits tels que lus dans les registres.
    public var words: [UInt32]
    public var isReadProtected: Bool
    public var isWriteProtected: Bool
}

/// Erreur d'encodage signalée par le contrôleur.
public struct EfuseCodingError: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// BLOCK0 : bits dont les copies diffèrent (`RD_REPEAT_ERR`), par mot.
        case repeatMismatch(word: Int, bits: UInt32)
        /// Reed-Solomon RS(44,32) : nombre d'octets corrigés, et échec si non corrigeable.
        case reedSolomon(correctedBytes: Int, failed: Bool)
        /// ESP32, codage 3/4 : avertissement de décodage.
        case threeQuarters(UInt32)
    }

    public var block: Int
    public var kind: Kind

    public var description: String {
        switch kind {
        case .repeatMismatch(let word, let bits): "BLOCK\(block) mot \(word) : copies différentes (0x\(String(bits, radix: 16)))"
        case .reedSolomon(let count, let failed):
            "BLOCK\(block) : \(failed ? "erreur RS non corrigeable" : "\(count) octet(s) corrigé(s) par RS")"
        case .threeQuarters(let value): "BLOCK\(block) : erreur de codage 3/4 (0x\(String(value, radix: 16)))"
        }
    }
}

/// Calibration ADC et capteur de température, telle qu'`espefuse adc-info` l'affiche.
public struct ADCCalibration: Hashable, Sendable {
    /// Version du bloc de calibration (`BLK_VERSION_MAJOR`…), quand la puce en a une.
    public var blockVersion: Int?
    /// Valeurs converties, par nom de champ (mV, codes, °C).
    public var values: [String: Double]
}

/// État complet, sérialisable : sert aux tests, à `EfuseController(virtual:)` et aux jetons.
public struct EfuseSnapshot: Hashable, Sendable, Codable {
    public var chip: ChipFamily
    /// Mots de chaque bloc, dans l'ordre des blocs.
    public var blocks: [[UInt32]]
    /// Registres d'erreur du contrôleur, dans l'ordre propre à la puce.
    public var errorRegisters: [UInt32]
    /// ESP32 : bit 31 du registre APB_CTRL_DATE, qui distingue les révisions 2 et 3.
    public var apbControlDate: UInt32?

    public init(chip: ChipFamily, blocks: [[UInt32]], errorRegisters: [UInt32] = [], apbControlDate: UInt32? = nil) {
        self.chip = chip
        self.blocks = blocks
        self.errorRegisters = errorRegisters
        self.apbControlDate = apbControlDate
    }
}

/// Erreurs des eFuses.
public enum EfuseError: ESPKitError, Equatable {
    case planInvalid([EfusePlanIssue])
    case verificationFailed(block: Int)
    case malformedToken
    /// Contrôleur créé depuis un jeton.
    case readOnly
    /// Puce dont ESPKit n'a pas la table ou les registres.
    case unsupportedChip(ChipFamily)

    public var description: String {
        switch self {
        case .planInvalid(let issues): "Plan de programmation invalide : \(issues.map(\.description).joined(separator: " ; "))"
        case .verificationFailed(let block): "Vérification du BLOCK\(block) échouée après programmation"
        case .malformedToken: "Jeton d'eFuses illisible"
        case .readOnly: "Contrôleur en lecture seule"
        case .unsupportedChip(let chip): "eFuses de \(chip) non pris en charge"
        }
    }
}
