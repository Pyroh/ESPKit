// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Erreurs d'analyse et de construction d'images.
public enum ImageError: ESPKitError, Equatable {
    case malformedImage(String)
    case malformedELF(String)
    case malformedIntelHex(line: Int, reason: String)
    /// Segments qui se chevauchent, alignement MMU impossible…
    case layout(String)
    case unsupportedChip(ChipFamily)
    /// Réglage d'en-tête qu'on ne sait pas encoder pour cette puce.
    case invalidHeaderSetting(String)

    public var description: String {
        switch self {
        case .malformedImage(let reason): "Image invalide : \(reason)"
        case .malformedELF(let reason): "ELF invalide : \(reason)"
        case .malformedIntelHex(let line, let reason): "Intel HEX invalide, ligne \(line) : \(reason)"
        case .layout(let reason): "Disposition impossible : \(reason)"
        case .unsupportedChip(let chip): "Format d'image non pris en charge pour \(chip)"
        case .invalidHeaderSetting(let reason): "Réglage d'en-tête invalide : \(reason)"
        }
    }
}

/// Résultat de `validate()` : une liste vide signifie que l'image est cohérente.
public struct ImageValidation: Hashable, Sendable {
    public enum Issue: Hashable, Sendable, CustomStringConvertible {
        case checksumMismatch(stored: UInt8, computed: UInt8)
        case digestMismatch
        case overlappingSegments(UInt32, UInt32)
        /// Segment mappé en flash dont l'offset dans le fichier ne correspond pas à son adresse
        /// modulo la page MMU.
        case misalignedFlashSegment(loadAddress: UInt32, fileOffset: Int)
        case crcMismatch(stored: UInt32, computed: UInt32)

        public var description: String {
            switch self {
            case .checksumMismatch(let stored, let computed):
                "somme de contrôle 0x\(String(stored, radix: 16)) au lieu de 0x\(String(computed, radix: 16))"
            case .digestMismatch: "empreinte SHA-256 invalide"
            case .overlappingSegments(let a, let b):
                "segments 0x\(String(a, radix: 16)) et 0x\(String(b, radix: 16)) se chevauchent"
            case .misalignedFlashSegment(let address, let offset):
                "segment flash 0x\(String(address, radix: 16)) mal aligné (offset 0x\(String(offset, radix: 16)))"
            case .crcMismatch(let stored, let computed):
                "CRC32 0x\(String(stored, radix: 16)) au lieu de 0x\(String(computed, radix: 16))"
            }
        }
    }

    public var issues: [Issue]
    public var isValid: Bool { issues.isEmpty }
}
