// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPSecure
import ESPTargets

/// Destination block of a key.
public enum KeyBlock: Hashable, Sendable, CustomStringConvertible {
    case key0, key1, key2, key3, key4, key5
    /// ESP32: BLOCK1, BLOCK2 (Secure Boot v1) and BLOCK2 (Secure Boot v2 digest, revision 3).
    case flashEncryption, secureBootV1, secureBootV2

    public var description: String {
        switch self {
        case .key0: "BLOCK_KEY0"
        case .key1: "BLOCK_KEY1"
        case .key2: "BLOCK_KEY2"
        case .key3: "BLOCK_KEY3"
        case .key4: "BLOCK_KEY4"
        case .key5: "BLOCK_KEY5"
        case .flashEncryption: "BLOCK1 (flash encryption)"
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

/// Flash voltage forced by eFuse (ESP32, S2, S3).
public enum FlashVoltage: Hashable, Sendable {
    case v1_8, v3_3, off
}

/// Intent token, the equivalent of typing "BURN" at the keyboard. No default value.
public enum BurnConfirmation: Sendable { case irreversible }

/// What to burn. A plain value: test it virtually, then replay it as is.
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
    /// Postpone to the very end the BLOCK0 bits that cut off access (`DIS_DOWNLOAD_MODE`…),
    /// like `--postpone` (default: yes).
    public var postponeLockingBits: Bool = true

    public init() {}

    public mutating func set(_ field: EfuseFieldName, to value: EfuseValue) { operations.append(.set(field, value)) }

    /// 32-byte key into an empty block (24 bytes on an ESP32 with the 3/4 coding scheme).
    /// Like espefuse: XTS-AES keys are byte-reversed
    /// for the AES peripheral, and only secret keys (encryption, HMAC,
    /// Secure Boot v1) are read-protected.
    public mutating func writeKey(_ key: Data, to block: KeyBlock, purpose: KeyPurpose,
                                  readProtect: Bool = true, writeProtect: Bool = true) {
        operations.append(.key(key, block, purpose, readProtect: readProtect, writeProtect: writeProtect))
    }

    /// Computes the public key digest (Secure Boot v2) and writes it, write-protected.
    public mutating func writeKeyDigest(_ publicKey: SecureBootV2.PublicKey, to block: KeyBlock, purpose: KeyPurpose) {
        operations.append(.keyDigest(publicKey, block, purpose))
    }

    /// Bytes added (logical OR) to the block from `offset`.
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

/// Problem that prevents a plan from running.
public struct EfusePlanIssue: Hashable, Sendable, CustomStringConvertible {
    public var operation: Int
    public var message: String
    public var description: String { "operation \(operation + 1): \(message)" }
}

/// Block word that will change. Bits only go from 0 to 1.
public struct EfuseChange: Hashable, Sendable, CustomStringConvertible {
    public var block: Int
    public var word: Int
    public var before: UInt32
    public var after: UInt32
    /// Bits of the word that will be burned.
    public var newBits: UInt32 { after & ~before }

    public var description: String {
        String(format: "BLOCK%d word %d: %08x → %08x", block, word, before, after)
    }
}

public struct EfuseBurnReport: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public var block: Int
        public var changes: [EfuseChange]
        /// BLOCK0 locking bits burned last.
        public var postponed: Bool
    }

    /// In execution order: from the last block down to BLOCK0, then the postponed bits.
    public var steps: [Step]
}

extension EfuseError {
    /// Burning a real chip is only written for the ESP32 (coding scheme NONE) for now.
    static func hardwareBurn(_ reason: String) -> EfuseError {
        .planInvalid([EfusePlanIssue(operation: 0, message: reason)])
    }
}

extension EfuseController {
    /// Checks the plan without writing anything: unknown field, value too wide, bits already 1 that
    /// would need to be 0, write-protected field, key block already used, purpose unknown to the chip…
    /// - Throws: `EfuseError.planInvalid` with the list of problems.
    /// - Returns: the words that change, block by block.
    public func preview(_ plan: EfuseBurnPlan) throws -> [EfuseChange] {
        try compile(plan).changes
    }

    /// Validates, then burns block by block (BLOCK0 last, locking bits at the very end),
    /// reads back and checks. Virtually, only the simulated state changes; as on the chip, a
    /// read-protected block then reads back as zeros.
    ///
    /// On a real chip: ESP32 only, coding scheme NONE (the 3/4 encoder is not verified on hardware
    /// yet; the other chips need their own sequence). Each block is programmed on its own, with
    /// only its new bits; after each one, every block is read back and ESPKit stops at the first
    /// bit the plan did not ask for. Irreversible.
    /// - Throws: `EfuseError.planInvalid`, `EfuseError.readOnly` (token),
    ///   `EfuseError.verificationFailed`, `EfuseError.unexpectedBits`, and on a chip the errors of
    ///   `ESPDevice.readRegister` / `writeRegister`.
    public func burn(_ plan: EfuseBurnPlan, confirm: BurnConfirmation) async throws -> EfuseBurnReport {
        guard !isReadOnly else { throw EfuseError.readOnly }
        // On a chip, the plan is checked against the eFuses as they are now.
        if connectedDevice != nil { try await reloadFromChip() }
        let compiled = try compile(plan)
        if let device = connectedDevice {
            return try await burnOnChip(compiled, postponing: plan.postponeLockingBits, device: device)
        }
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
        // Read-back: every requested bit must be 1, except in blocks that became unreadable.
        let hidden = readProtectedBlocks()
        for block in compiled.target.indices where !hidden.contains(block) {
            for word in compiled.target[block].indices where state.blocks[block][word] & compiled.target[block][word] != compiled.target[block][word] {
                throw EfuseError.verificationFailed(block: block)
            }
        }
        for block in hidden { state.blocks[block] = state.blocks[block].map { _ in 0 } }
        return EfuseBurnReport(steps: steps)
    }

    // MARK: Plan compilation

    struct CompiledPlan {
        var target: [[UInt32]]
        var changes: [EfuseChange]
        /// BLOCK0: locking bits, per word.
        var lockingMask: [Int: UInt32]
    }

    private func compile(_ plan: EfuseBurnPlan) throws -> CompiledPlan {
        guard let table = efuseTable else { throw EfuseError.unsupportedChip(chip) }
        var target = state.blocks
        var issues: [EfusePlanIssue] = []

        func fail(_ index: Int, _ message: String) { issues.append(EfusePlanIssue(operation: index, message: message)) }
        func definition(_ index: Int, _ name: String) -> EfuseDefinition? {
            if let found = table.definition(named: name) { return found }
            fail(index, "unknown field \(name) on \(chip)")
            return nil
        }
        /// Sets `bits` (least significant first) in the field, refusing any bit that would go back to 0.
        func write(_ index: Int, _ field: EfuseDefinition, bits: [Bool]) {
            guard bits.count <= field.bitCount else {
                fail(index, "\(field.name): \(bits.count)-bit value for a \(field.bitCount)-bit field")
                return
            }
            if isWriteProtected(field) { fail(index, "\(field.name) is write-protected") }
            var position = 0
            for range in field.bits {
                for bit in range.start..<range.start + range.count {
                    let wanted = position < bits.count && bits[position]
                    let word = bit / 32, mask = UInt32(1) << UInt32(bit % 32)
                    let current = target[field.block][word] & mask != 0
                    if current && !wanted && state.blocks[field.block][word] & mask != 0 {
                        fail(index, "\(field.name): bit \(bit) is already 1 and cannot go back to 0")
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
                        fail(index, "\(field.name): \(number) does not fit in \(field.bitCount) bits")
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
                guard block < target.count else { fail(index, "BLOCK\(block) does not exist"); continue }
                guard offset >= 0, offset + data.count <= byteCount(ofBlock: block) else {
                    fail(index, "\(data.count) bytes at offset \(offset) go past BLOCK\(block)")
                    continue
                }
                if blocks()[block].isWriteProtected { fail(index, "BLOCK\(block) is write-protected") }
                for (i, byte) in data.enumerated() {
                    let position = offset + i
                    target[block][position / 4] |= UInt32(byte) << UInt32(8 * (position % 4))
                }

            case .bits(let bits, let block):
                guard block < target.count else { fail(index, "BLOCK\(block) does not exist"); continue }
                if blocks()[block].isWriteProtected { fail(index, "BLOCK\(block) is write-protected") }
                for bit in bits {
                    guard bit >= 0, bit < byteCount(ofBlock: block) * 8 else { fail(index, "bit \(bit) outside BLOCK\(block)"); continue }
                    target[block][bit / 32] |= 1 << UInt32(bit % 32)
                }

            case .readProtect(let name):
                guard let field = definition(index, name.rawValue) else { continue }
                guard field.readDisableBit != nil else { fail(index, "\(field.name) cannot be read-protected"); continue }
                setBit(index, "RD_DIS", bit: field.readDisableBit)

            case .writeProtect(let name):
                guard let field = definition(index, name.rawValue) else { continue }
                guard field.writeDisableBit != nil else { fail(index, "\(field.name) cannot be write-protected"); continue }
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
                default: fail(index, "\(chip) has no flash regulator set by eFuse"); continue
                }
                // Force the setting, then: 1.8 V = regulator only; 3.3 V = regulator + VDD3P3; off = nothing.
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
            default: fail(index, "the ESP32 has no \(block)"); return
            }
        } else {
            guard let key = block.keyIndex else { fail(index, "\(chip) has no \(block)"); return }
            blockField = table.definition(named: "BLOCK_KEY\(key)")
            purposeField = table.definition(named: "KEY_PURPOSE_\(key)")
            guard purposeField != nil else { fail(index, "\(chip) has no key purpose for \(block)"); return }
        }
        guard let blockField else { fail(index, "\(block) not found on \(chip)"); return }
        // Under the ESP32's 3/4 coding scheme, keys are 192 bits.
        let keyLength = usesThreeQuartersCoding ? 24 : 32
        guard key.count == keyLength else { fail(index, "\(key.count)-byte key; \(keyLength) expected"); return }
        if digest, ![.secureBootDigest0, .secureBootDigest1, .secureBootDigest2].contains(purpose), chip != .esp32 {
            fail(index, "a Secure Boot digest needs a SECURE_BOOT_DIGESTn purpose")
            return
        }
        if rawValue(blockField) != 0 || (purposeField.map(rawValue) ?? 0) != 0 {
            fail(index, "\(block) is already used")
            return
        }
        // AES keys (XTS, and on the ESP32 flash encryption and Secure Boot v1) are stored reversed.
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
