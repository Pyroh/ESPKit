// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSecure
import ESPTargets

/// Bloc destinataire d'une clé.
public enum KeyBlock: Hashable, Sendable, CustomStringConvertible {
    case key0, key1, key2, key3, key4, key5
    /// ESP32 : BLOCK1, BLOCK2 (Secure Boot v1) et BLOCK2 (digest Secure Boot v2, révision 3).
    case flashEncryption, secureBootV1, secureBootV2

    public var description: String {
        switch self {
        case .key0: "BLOCK_KEY0"
        case .key1: "BLOCK_KEY1"
        case .key2: "BLOCK_KEY2"
        case .key3: "BLOCK_KEY3"
        case .key4: "BLOCK_KEY4"
        case .key5: "BLOCK_KEY5"
        case .flashEncryption: "BLOCK1 (chiffrement flash)"
        case .secureBootV1: "BLOCK2 (Secure Boot v1)"
        case .secureBootV2: "BLOCK2 (Secure Boot v2)"
        }
    }

    var keyIndex: Int? {
        switch self {
        case .key0: 0
        case .key1: 1
        case .key2: 2
        case .key3: 3
        case .key4: 4
        case .key5: 5
        default: nil
        }
    }
}

/// Tension de la flash forcée par eFuse (ESP32, S2, S3).
public enum FlashVoltage: Hashable, Sendable {
    case v1_8, v3_3, off
}

/// Jeton d'intention, équivalent du « BURN » tapé au clavier. Pas de valeur par défaut.
public enum BurnConfirmation: Sendable { case irreversible }

/// Ce qu'on veut brûler. Une simple valeur : on la teste en virtuel, puis on la rejoue telle quelle.
public struct EfuseBurnPlan: Sendable {
    enum Operation: Sendable {
        case set(EfuseFieldName, EfuseValue)
        case key(Data, KeyBlock, KeyPurpose, readProtect: Bool, writeProtect: Bool)
        case keyDigest(SecureBootV2.PublicKey, KeyBlock, KeyPurpose)
        case blockData(Data, block: Int, offset: Int)
        case bits([Int], block: Int)
        case readProtect(EfuseFieldName)
        case writeProtect(EfuseFieldName)
        case customMAC(MACAddress)
        case flashVoltage(FlashVoltage)
    }

    var operations: [Operation] = []
    /// Repousser à la fin les bits de BLOCK0 qui coupent l'accès (`DIS_DOWNLOAD_MODE`…),
    /// comme `--postpone` (défaut : oui).
    public var postponeLockingBits: Bool = true

    public init() {}

    public mutating func set(_ field: EfuseFieldName, to value: EfuseValue) { operations.append(.set(field, value)) }

    /// Clé de 32 octets dans un bloc vide. Comme espefuse : les clés XTS-AES sont retournées
    /// octet par octet pour le périphérique AES, et seules les clés secrètes (chiffrement, HMAC,
    /// Secure Boot v1) sont protégées en lecture.
    public mutating func writeKey(_ key: Data, to block: KeyBlock, purpose: KeyPurpose,
                                  readProtect: Bool = true, writeProtect: Bool = true) {
        operations.append(.key(key, block, purpose, readProtect: readProtect, writeProtect: writeProtect))
    }

    /// Calcule le digest de la clé publique (Secure Boot v2) et l'écrit, protégé en écriture.
    public mutating func writeKeyDigest(_ publicKey: SecureBootV2.PublicKey, to block: KeyBlock, purpose: KeyPurpose) {
        operations.append(.keyDigest(publicKey, block, purpose))
    }

    /// Octets ajoutés (OU logique) au bloc à partir de `offset`.
    public mutating func writeBlockData(_ data: Data, to block: Int, offset: Int = 0) {
        operations.append(.blockData(data, block: block, offset: offset))
    }

    public mutating func burnBits(_ bits: [Int], in block: Int) { operations.append(.bits(bits, block: block)) }
    public mutating func readProtect(_ field: EfuseFieldName) { operations.append(.readProtect(field)) }
    public mutating func writeProtect(_ field: EfuseFieldName) { operations.append(.writeProtect(field)) }
    public mutating func setCustomMAC(_ mac: MACAddress) { operations.append(.customMAC(mac)) }
    /// ESP32, S2, S3.
    public mutating func setFlashVoltage(_ voltage: FlashVoltage) { operations.append(.flashVoltage(voltage)) }
}

/// Problème qui empêche d'exécuter un plan.
public struct EfusePlanIssue: Hashable, Sendable, CustomStringConvertible {
    public var operation: Int
    public var message: String
    public var description: String { "opération \(operation + 1) : \(message)" }
}

/// Mot d'un bloc qui va changer. Seuls des bits passent de 0 à 1.
public struct EfuseChange: Hashable, Sendable, CustomStringConvertible {
    public var block: Int
    public var word: Int
    public var before: UInt32
    public var after: UInt32
    /// Bits du mot qui seront brûlés.
    public var newBits: UInt32 { after & ~before }

    public var description: String {
        String(format: "BLOCK%d mot %d : %08x → %08x", block, word, before, after)
    }
}

public struct EfuseBurnReport: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public var block: Int
        public var changes: [EfuseChange]
        /// Bits de verrouillage de BLOCK0 brûlés en dernier.
        public var postponed: Bool
    }

    /// Dans l'ordre d'exécution : du dernier bloc vers BLOCK0, puis les bits repoussés.
    public var steps: [Step]
}

extension EfuseError {
    /// La programmation sur une vraie puce n'est pas encore ouverte : seul le contrôleur virtuel brûle.
    static let hardwareBurn = EfuseError.planInvalid([EfusePlanIssue(operation: 0,
        message: "la programmation sur une vraie puce n'est pas encore disponible ; utiliser EfuseController(virtual:)")])
}

extension EfuseController {
    /// Vérifie le plan sans rien écrire : champ inconnu, valeur trop large, bits déjà à 1 qu'on
    /// voudrait à 0, champ protégé en écriture, bloc de clé déjà utilisé, rôle inconnu de la puce…
    /// - Throws: `EfuseError.planInvalid` avec la liste des problèmes.
    /// - Returns: les mots qui changent, bloc par bloc.
    public func preview(_ plan: EfuseBurnPlan) throws -> [EfuseChange] {
        try compile(plan).changes
    }

    /// Valide, puis brûle bloc par bloc (BLOCK0 en dernier, bits de verrouillage à la toute fin),
    /// relit et contrôle. En virtuel, ne modifie que l'état simulé ; comme sur la puce, un bloc
    /// protégé en lecture se relit ensuite à zéro.
    /// - Throws: `EfuseError.planInvalid`, `EfuseError.readOnly` (jeton),
    ///   `EfuseError.verificationFailed`.
    public func burn(_ plan: EfuseBurnPlan, confirm: BurnConfirmation) async throws -> EfuseBurnReport {
        guard !isReadOnly else { throw EfuseError.readOnly }
        guard isVirtual else { throw EfuseError.hardwareBurn }
        let compiled = try compile(plan)
        var steps: [EfuseBurnReport.Step] = []
        let postponed = plan.postponeLockingBits ? compiled.lockingMask : [:]
        for block in compiled.target.indices.reversed() {
            var changes: [EfuseChange] = []
            for word in compiled.target[block].indices {
                var after = compiled.target[block][word]
                if block == 0 { after &= ~(postponed[word] ?? 0) | (state.blocks[0][word]) }
                let before = state.blocks[block][word]
                if after != before { changes.append(EfuseChange(block: block, word: word, before: before, after: after)) }
            }
            guard !changes.isEmpty else { continue }
            apply(changes)
            steps.append(.init(block: block, changes: changes, postponed: false))
        }
        var late: [EfuseChange] = []
        for (word, _) in postponed.sorted(by: { $0.key < $1.key }) where compiled.target[0][word] != state.blocks[0][word] {
            late.append(EfuseChange(block: 0, word: word, before: state.blocks[0][word], after: compiled.target[0][word]))
        }
        if !late.isEmpty {
            apply(late)
            steps.append(.init(block: 0, changes: late, postponed: true))
        }
        // Relecture : chaque bit demandé doit être à 1, sauf dans les blocs devenus illisibles.
        let hidden = readProtectedBlocks()
        for block in compiled.target.indices where !hidden.contains(block) {
            for word in compiled.target[block].indices where state.blocks[block][word] & compiled.target[block][word] != compiled.target[block][word] {
                throw EfuseError.verificationFailed(block: block)
            }
        }
        for block in hidden { state.blocks[block] = state.blocks[block].map { _ in 0 } }
        return EfuseBurnReport(steps: steps)
    }

    // MARK: Compilation du plan

    struct CompiledPlan {
        var target: [[UInt32]]
        var changes: [EfuseChange]
        /// BLOCK0 : bits de verrouillage, par mot.
        var lockingMask: [Int: UInt32]
    }

    private func compile(_ plan: EfuseBurnPlan) throws -> CompiledPlan {
        guard let table = efuseTable else { throw EfuseError.unsupportedChip(chip) }
        var target = state.blocks
        var issues: [EfusePlanIssue] = []

        func fail(_ index: Int, _ message: String) { issues.append(EfusePlanIssue(operation: index, message: message)) }
        func definition(_ index: Int, _ name: String) -> EfuseDefinition? {
            if let found = table.definition(named: name) { return found }
            fail(index, "champ \(name) inconnu sur \(chip)")
            return nil
        }
        /// Pose `bits` (poids faible d'abord) dans le champ, en refusant tout bit à remettre à 0.
        func write(_ index: Int, _ field: EfuseDefinition, bits: [Bool]) {
            guard bits.count <= field.bitCount else {
                fail(index, "\(field.name) : valeur sur \(bits.count) bits pour un champ de \(field.bitCount)")
                return
            }
            if isWriteProtected(field) { fail(index, "\(field.name) est protégé en écriture") }
            var position = 0
            for range in field.bits {
                for bit in range.start..<range.start + range.count {
                    let wanted = position < bits.count && bits[position]
                    let word = bit / 32, mask = UInt32(1) << UInt32(bit % 32)
                    let current = target[field.block][word] & mask != 0
                    if current && !wanted && state.blocks[field.block][word] & mask != 0 {
                        fail(index, "\(field.name) : le bit \(bit) est déjà à 1 et ne peut pas revenir à 0")
                        return
                    }
                    if wanted { target[field.block][word] |= mask }
                    position += 1
                }
            }
        }
        func integerBits(_ value: UInt64, count: Int) -> [Bool] { (0..<count).map { value >> UInt64($0) & 1 == 1 } }
        func byteBits(_ data: Data) -> [Bool] { data.flatMap { byte in (0..<8).map { byte >> UInt8($0) & 1 == 1 } } }
        func setBit(_ index: Int, _ table: String, bit: Int?) {
            guard let bit, let field = definition(index, table) else { return }
            write(index, field, bits: integerBits(rawValue(field) | 1 << UInt64(bit), count: field.bitCount))
        }

        for (index, operation) in plan.operations.enumerated() {
            switch operation {
            case .set(let name, let value):
                guard let field = definition(index, name.rawValue) else { continue }
                switch value {
                case .bool(let flag): write(index, field, bits: [flag])
                case .uint(let number):
                    guard field.bitCount >= 64 || number >> UInt64(field.bitCount) == 0 else {
                        fail(index, "\(field.name) : \(number) ne tient pas sur \(field.bitCount) bits")
                        continue
                    }
                    write(index, field, bits: integerBits(number, count: field.bitCount))
                case .bytes(let data): write(index, field, bits: byteBits(data))
                case .mac(let mac): write(index, field, bits: byteBits(mac.bytes))
                case .keyPurpose(let purpose): write(index, field, bits: integerBits(UInt64(purpose.rawCode), count: field.bitCount))
                }

            case .key(let key, let block, let purpose, let readProtect, let writeProtect):
                writeKey(index, key, block: block, purpose: purpose, readProtect: readProtect, writeProtect: writeProtect,
                         digest: false, table: table, write: write, fail: fail, setBit: setBit, integerBits: integerBits)

            case .keyDigest(let publicKey, let block, let purpose):
                writeKey(index, publicKey.digest, block: block, purpose: purpose, readProtect: false, writeProtect: true,
                         digest: true, table: table, write: write, fail: fail, setBit: setBit, integerBits: integerBits)

            case .blockData(let data, let block, let offset):
                guard block < target.count else { fail(index, "BLOCK\(block) n'existe pas"); continue }
                guard offset >= 0, offset + data.count <= target[block].count * 4 else {
                    fail(index, "\(data.count) octets à l'offset \(offset) débordent du BLOCK\(block)")
                    continue
                }
                if blocks()[block].isWriteProtected { fail(index, "BLOCK\(block) est protégé en écriture") }
                for (i, byte) in data.enumerated() {
                    let position = offset + i
                    target[block][position / 4] |= UInt32(byte) << UInt32(8 * (position % 4))
                }

            case .bits(let bits, let block):
                guard block < target.count else { fail(index, "BLOCK\(block) n'existe pas"); continue }
                if blocks()[block].isWriteProtected { fail(index, "BLOCK\(block) est protégé en écriture") }
                for bit in bits {
                    guard bit >= 0, bit < target[block].count * 32 else { fail(index, "bit \(bit) hors du BLOCK\(block)"); continue }
                    target[block][bit / 32] |= 1 << UInt32(bit % 32)
                }

            case .readProtect(let name):
                guard let field = definition(index, name.rawValue) else { continue }
                guard field.readDisableBit != nil else { fail(index, "\(field.name) ne peut pas être protégé en lecture"); continue }
                setBit(index, "RD_DIS", bit: field.readDisableBit)

            case .writeProtect(let name):
                guard let field = definition(index, name.rawValue) else { continue }
                guard field.writeDisableBit != nil else { fail(index, "\(field.name) ne peut pas être protégé en écriture"); continue }
                setBit(index, "WR_DIS", bit: field.writeDisableBit)

            case .customMAC(let mac):
                if chip == .esp32 {
                    guard let field = definition(index, "MAC_CUSTOM"), let crc = definition(index, "CUSTOM_MAC_CRC"),
                          let version = definition(index, "MAC_VERSION") else { continue }
                    write(index, field, bits: byteBits(mac.bytes))
                    write(index, crc, bits: integerBits(UInt64(EfuseController.crc8(mac.bytes)), count: 8))
                    write(index, version, bits: integerBits(1, count: version.bitCount))
                } else if let field = definition(index, "CUSTOM_MAC") {
                    write(index, field, bits: byteBits(mac.bytes))
                }

            case .flashVoltage(let voltage):
                let names: (force: String, regulator: String, high: String)
                switch chip {
                case .esp32: names = ("XPD_SDIO_FORCE", "XPD_SDIO_REG", "XPD_SDIO_TIEH")
                case .esp32s2, .esp32s3: names = ("VDD_SPI_FORCE", "VDD_SPI_XPD", "VDD_SPI_TIEH")
                default: fail(index, "\(chip) n'a pas de régulateur de flash réglable par eFuse"); continue
                }
                // Forcer le réglage, puis : 1,8 V = régulateur seul ; 3,3 V = régulateur + VDD3P3 ; arrêt = rien.
                guard let force = definition(index, names.force), let regulator = definition(index, names.regulator),
                      let high = definition(index, names.high) else { continue }
                write(index, force, bits: [true])
                if voltage != .off { write(index, regulator, bits: [true]) }
                if voltage == .v3_3 { write(index, high, bits: [true]) }
            }
        }
        guard issues.isEmpty else { throw EfuseError.planInvalid(issues) }

        var changes: [EfuseChange] = []
        for block in target.indices {
            for word in target[block].indices where target[block][word] != state.blocks[block][word] {
                changes.append(EfuseChange(block: block, word: word, before: state.blocks[block][word], after: target[block][word]))
            }
        }
        var locking: [Int: UInt32] = [:]
        for name in ["DIS_DOWNLOAD_MODE", "ENABLE_SECURITY_DOWNLOAD", "UART_DOWNLOAD_DIS"] {
            guard let field = table.definition(named: name), field.block == 0 else { continue }
            for range in field.bits {
                for bit in range.start..<range.start + range.count { locking[bit / 32, default: 0] |= 1 << UInt32(bit % 32) }
            }
        }
        return CompiledPlan(target: target, changes: changes, lockingMask: locking)
    }

    // swiftlint:disable:next function_parameter_count
    private func writeKey(_ index: Int, _ key: Data, block: KeyBlock, purpose: KeyPurpose, readProtect: Bool,
                          writeProtect: Bool, digest: Bool, table: EfuseTable,
                          write: (Int, EfuseDefinition, [Bool]) -> Void, fail: (Int, String) -> Void,
                          setBit: (Int, String, Int?) -> Void, integerBits: (UInt64, Int) -> [Bool]) {
        let blockField: EfuseDefinition?
        var purposeField: EfuseDefinition?
        if chip == .esp32 {
            switch block {
            case .flashEncryption: blockField = table.definition(named: "BLOCK1")
            case .secureBootV1, .secureBootV2: blockField = table.definition(named: "BLOCK2")
            default: fail(index, "l'ESP32 n'a pas de \(block)"); return
            }
        } else {
            guard let key = block.keyIndex else { fail(index, "\(chip) n'a pas de \(block)"); return }
            blockField = table.definition(named: "BLOCK_KEY\(key)")
            purposeField = table.definition(named: "KEY_PURPOSE_\(key)")
            guard purposeField != nil else { fail(index, "\(chip) n'a pas de rôle de clé pour \(block)"); return }
        }
        guard let blockField else { fail(index, "\(block) introuvable sur \(chip)"); return }
        guard key.count == 32 else { fail(index, "clé de \(key.count) octets ; 32 attendus"); return }
        if digest, ![.secureBootDigest0, .secureBootDigest1, .secureBootDigest2].contains(purpose), chip != .esp32 {
            fail(index, "un digest Secure Boot veut un rôle SECURE_BOOT_DIGESTn")
            return
        }
        if rawValue(blockField) != 0 || (purposeField.map(rawValue) ?? 0) != 0 {
            fail(index, "\(block) est déjà utilisé")
            return
        }
        // Les clés AES (XTS, et sur ESP32 chiffrement flash et Secure Boot v1) sont rangées à l'envers.
        let reversed = !digest && (chip == .esp32
            ? block != .secureBootV2
            : [.xtsAES128Key, .xtsAES256Key1, .xtsAES256Key2].contains(purpose))
        let bytes = reversed ? Data(key.reversed()) : key
        write(index, blockField, bytes.flatMap { byte in (0..<8).map { byte >> UInt8($0) & 1 == 1 } })
        if let purposeField { write(index, purposeField, integerBits(UInt64(purpose.rawCode), purposeField.bitCount)) }
        let secret = !digest && (chip == .esp32 ? block != .secureBootV2
            : [.xtsAES128Key, .xtsAES256Key1, .xtsAES256Key2, .hmacDownAll, .hmacDownJTAG,
               .hmacDownDigitalSignature, .hmacUp].contains(purpose))
        if readProtect && secret { setBit(index, "RD_DIS", blockField.readDisableBit) }
        if writeProtect {
            setBit(index, "WR_DIS", blockField.writeDisableBit)
            if let purposeField { setBit(index, "WR_DIS", purposeField.writeDisableBit) }
        }
    }
}
