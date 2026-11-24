// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Échecs d'établissement ou d'utilisation de la session.
public enum ConnectionError: ESPKitError, Equatable {
    /// Aucune réponse au SYNC après toutes les tentatives.
    case noResponse(attempts: Int)
    case chipMismatch(expected: ChipFamily, detected: ChipFamily)
    case unknownChip(magic: UInt32?, chipID: UInt32?)
    /// Aucun port ne correspond au filtre de `connectFirstAvailable`.
    case noMatchingPort
    /// Opération sur un `ESPDevice` après `disconnect`, `loadRAMAndRun` ou `runFlashApplication`.
    case disconnected

    public var description: String {
        switch self {
        case .noResponse(let attempts):
            "La puce ne répond pas (\(attempts) tentative(s)). Vérifier le câble, le port et le mode de boot."
        case .chipMismatch(let expected, let detected):
            "Puce inattendue : \(expected) demandée, \(detected) détectée"
        case .unknownChip(let magic, let chipID):
            "Puce non reconnue (magic \(magic.map(hex) ?? "—"), chip ID \(chipID.map(String.init) ?? "—"))"
        case .noMatchingPort:
            "Aucun port série ne correspond au filtre"
        case .disconnected:
            "La session est fermée"
        }
    }
}

/// Erreurs d'échange avec la ROM ou le stub.
public enum ProtocolError: ESPKitError, Equatable {
    case timeout(opcode: UInt8?, after: Duration)
    case invalidResponse(String)
    /// La ROM ou le stub a répondu par un échec.
    case deviceError(opcode: UInt8, code: DeviceErrorCode)

    public var description: String {
        switch self {
        case .timeout(let opcode, let after):
            "Pas de réponse à la commande \(opcode.map(hex) ?? "?") après \(after)"
        case .invalidResponse(let reason):
            "Réponse incohérente : \(reason)"
        case .deviceError(let opcode, let code):
            "La puce a refusé la commande \(hex(opcode)) : \(code)"
        }
    }
}

/// Codes d'échec de la ROM ou du stub. Un code inconnu est conservé tel quel.
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

    // Codes du stub v2 (octet de poids fort de son code de réponse).
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
        case 0x05: "message invalide"
        case 0x06: "échec de l'action"
        case 0x07: "CRC invalide"
        case 0x08: "erreur d'écriture flash"
        case 0x09: "erreur de lecture flash"
        case 0x0A: "longueur de lecture flash invalide"
        case 0x0B: "erreur de décompression"
        case 0xC0: "longueur de données incorrecte"
        case 0xC1: "somme de contrôle incorrecte"
        case 0xC2: "taille de bloc incorrecte"
        case 0xC3: "commande invalide"
        case 0xC4: "échec de l'opération SPI"
        case 0xC5: "échec du déverrouillage SPI"
        case 0xC6: "pas d'écriture en cours"
        case 0xC7: "erreur de décompression"
        case 0xC8: "données insuffisantes"
        case 0xC9: "trop de données"
        case 0xCA: "échec de programmation NAND"
        case 0xCB: "échec d'effacement NAND"
        case 0xFF: "commande non implémentée"
        default: nil
        }
        return name.map { "\($0) (\(hex(rawValue)))" } ?? "code \(hex(rawValue))"
    }
}

/// Mauvais usage de l'API, ou opération impossible dans l'état courant de la puce.
public enum UsageError: ESPKitError, Equatable {
    case unsupported(feature: String, chip: ChipFamily, state: ESPDevice.State)
    case unavailableInSecureDownloadMode(operation: String)
    case invalidArgument(String)
    /// Contournable par `force`.
    case securityRestriction(String)
    /// Contournable par `force`.
    case imageIncompatible(String)

    public var description: String {
        switch self {
        case .unsupported(let feature, let chip, let state):
            "\(feature) n'est pas disponible sur \(chip) (\(state))"
        case .unavailableInSecureDownloadMode(let operation):
            "\(operation) est impossible en Secure Download Mode"
        case .invalidArgument(let reason):
            "Argument invalide : \(reason)"
        case .securityRestriction(let reason):
            "Refusé par sécurité : \(reason) (contournable avec `force`)"
        case .imageIncompatible(let reason):
            "Image incompatible : \(reason) (contournable avec `force`)"
        }
    }
}

/// Erreurs propres à la flash.
public enum FlashError: ESPKitError, Equatable {
    case md5Mismatch(address: UInt32, expected: MD5Digest, actual: MD5Digest)
    /// RDID rend 0x000000, 0xFFFFFF ou 0xFFFF3F : aucune flash ne répond sur le bus SPI.
    case notDetected(jedecID: UInt32)

    public var description: String {
        switch self {
        case .md5Mismatch(let address, let expected, let actual):
            "MD5 différent à \(hex(address)) : attendu \(expected), lu \(actual)"
        case .notDetected(let id):
            "Aucune flash ne répond (ID JEDEC \(hex(id))). Vérifier le câblage SPI."
        }
    }
}

/// Erreurs liées au stub.
public enum StubError: ESPKitError, Equatable {
    /// JSON illisible, segment vide, adresse mal alignée.
    case malformed(String)
    case chipMismatch(stub: ChipFamily, device: ChipFamily)
    /// Segments qui se recouvrent, ou recouvrent le BSS.
    case overlapping(String)
    /// Aucun stub embarqué pour cette puce.
    case noBundledStub(ChipFamily)
    /// Pas de `OHAI` après le lancement.
    case failedToStart(StubImage.Version)

    public var description: String {
        switch self {
        case .malformed(let reason): "Image de stub invalide : \(reason)"
        case .chipMismatch(let stub, let device): "Stub prévu pour \(stub), puce connectée : \(device)"
        case .overlapping(let reason): "Segments de stub incohérents : \(reason)"
        case .noBundledStub(let chip): "Aucun stub embarqué pour \(chip)"
        case .failedToStart(let version): "Le stub \(version) n'a pas démarré (pas de OHAI)"
        }
    }
}

func hex<T: FixedWidthInteger>(_ value: T) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}
