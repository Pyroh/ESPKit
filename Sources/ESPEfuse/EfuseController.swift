// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPDevice
import ESPTargets

/// eFuse reading: raw blocks, decoded fields, coding errors, calibration.
///
/// Blocks are read register by register (`READ_REG`), under ROM as under the stub. Fields
/// come from the ESP-IDF tables; their presentation (`displayValue`, `summaryJSON()`) is aligned
/// with espefuse's.
public actor EfuseController {
    /// The chip whose eFuses this controller reads.
    public nonisolated let chip: ChipFamily
    var state: EfuseSnapshot
    private let device: ESPDevice?
    private let table: EfuseTable?
    /// Controller created from a token: no writes possible.
    public nonisolated let isReadOnly: Bool

    /// Reads every block through the registers (ROM or stub, either works).
    /// - Throws: `EfuseError.unsupportedChip` (registers unknown for this chip: ESPKit knows
    ///   those of the ESP32 and ESP32-S3), and the errors of `ESPDevice.readRegister`.
    public init(device: ESPDevice) async throws {
        guard let layout = EfuseLayout.layout(for: device.chip), let table = EfuseTable.table(for: device.chip) else {
            throw EfuseError.unsupportedChip(device.chip)
        }
        self.chip = device.chip
        self.device = device
        self.table = table
        self.isReadOnly = false
        self.state = try await Self.read(layout, chip: device.chip, from: device)
    }

    /// Simulated controller, blank or with a given state. Nothing is sent to a chip.
    public init(virtual chip: ChipFamily, initialState: EfuseSnapshot? = nil) {
        self.chip = chip
        self.device = nil
        self.table = EfuseTable.table(for: chip)
        self.isReadOnly = false
        self.state = initialState ?? EfuseSnapshot(chip: chip, blocks: EfuseLayout.blankBlocks(for: chip))
    }

    /// Read-only, from an `EFSR:<chip>:…` token produced by `token()`.
    /// - Throws: `EfuseError.malformedToken`.
    public init(token: String) throws {
        let parts = token.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "EFSR", let chip = ChipFamily(rawValue: parts[1]),
              let data = Data(base64Encoded: parts[2]),
              let snapshot = try? JSONDecoder().decode(EfuseSnapshot.self, from: data), snapshot.chip == chip
        else { throw EfuseError.malformedToken }
        self.chip = chip
        self.device = nil
        self.table = EfuseTable.table(for: chip)
        self.isReadOnly = true
        self.state = snapshot
    }

    /// Reads the blocks again from the chip; no effect for a virtual controller or a token.
    public func refresh() async throws {
        guard let device, let layout = EfuseLayout.layout(for: chip) else { return }
        state = try await Self.read(layout, chip: chip, from: device)
    }

    /// The whole state as a value, to save or to start a virtual controller from.
    public func snapshot() -> EfuseSnapshot { state }

    /// The state as an `EFSR:<chip>:<base64>` string, for ``init(token:)``.
    public func token() -> String {
        let data = (try? JSONEncoder().encode(state)) ?? Data()
        return "EFSR:\(chip.rawValue):\(data.base64EncodedString())"
    }

    // MARK: Reading

    /// Every block as read, BLOCK0 first. Read-protected blocks read as zeros; under the ESP32's
    /// 3/4 coding scheme BLOCK1 to BLOCK3 have 6 words.
    public func blocks() -> [EfuseBlock] {
        let names = EfuseLayout.layout(for: chip)?.blocks.map(\.name)
        return state.blocks.enumerated().map { index, words in
            let whole = table?.fields.first { $0.block == index && $0.bitCount >= 192 }
            return EfuseBlock(index: index, name: names?[safe: index] ?? "BLOCK\(index)",
                              words: Array(words.prefix(byteCount(ofBlock: index) / 4)),
                              isReadProtected: whole.map(isReadProtected) ?? false,
                              isWriteProtected: whole.map(isWriteProtected) ?? false)
        }
    }

    /// Every field of the table, computed fields included.
    public func fields() -> [EfuseField] {
        guard let table else { return [] }
        return table.fields.map(field(for:)) + table.composites.compactMap(composite(for:))
    }

    /// One field by name (ESP-IDF name or espefuse alias); `nil` if the chip has no such field.
    public func field(_ name: EfuseFieldName) -> EfuseField? {
        guard let table else { return nil }
        if let definition = table.definition(named: name.rawValue) { return field(for: definition) }
        return table.composites.first { $0.name == name.rawValue }.flatMap(composite(for:))
    }

    /// RS(44,32), repeat (BLOCK0) or 3/4 (ESP32) coding errors detected by the controller.
    public func codingErrors() -> [EfuseCodingError] {
        let registers = state.errorRegisters
        switch chip {
        case .esp32:
            guard let status = registers.first, raw("CODING_SCHEME") == 1, status & 0xFFF != 0 else { return [] }
            return [EfuseCodingError(block: 1, kind: .threeQuarters(status & 0xFFF))]
        case .esp32s3 where registers.count == 7:
            var errors: [EfuseCodingError] = []
            for (index, bits) in registers.prefix(5).enumerated() where bits != 0 {
                errors.append(EfuseCodingError(block: 0, kind: .repeatMismatch(word: index + 1, bits: bits)))
            }
            // Four bits per block: number of corrected bytes (3 bits), then failure.
            for block in 1...10 {
                let register = block <= 8 ? registers[5] : registers[6]
                let nibble = register >> UInt32(4 * ((block - 1) % 8)) & 0xF
                if nibble != 0 {
                    errors.append(EfuseCodingError(block: block, kind: .reedSolomon(correctedBytes: Int(nibble & 7),
                                                                                    failed: nibble & 8 != 0)))
                }
            }
            return errors
        default:
            return []
        }
    }

    /// Calibration converted like `espefuse adc-info`. `nil` if the chip has none or ESPKit
    /// cannot convert it yet (only the ESP32 and ESP32-S3 are verified).
    public func adcCalibration() -> ADCCalibration? {
        switch chip {
        case .esp32:
            guard let vref = field("ADC_VREF"), case .uint = vref.value else { return nil }
            return ADCCalibration(blockVersion: nil, values: ["ADC_VREF": Double(vref.displayValue) ?? 0])
        case .esp32s3:
            let major = raw("BLK_VERSION_MAJOR") ?? 0, minor = raw("BLK_VERSION_MINOR") ?? 0
            guard major != 0 else { return ADCCalibration(blockVersion: 0, values: [:]) }
            var values: [String: Double] = [:]
            for field in fields() where field.category == "calibration" {
                values[field.name.rawValue] = Double(field.displayValue)
            }
            return ADCCalibration(blockVersion: Int(major * 100 + minor), values: values)
        default:
            return nil
        }
    }

    /// Custom MAC, `nil` if it is not programmed (all bytes 0).
    public func customMAC() -> MACAddress? {
        guard let field = field("CUSTOM_MAC") ?? field("MAC_CUSTOM"), case .mac(let mac) = field.value,
              mac.bytes.contains(where: { $0 != 0 }) else { return nil }
        return mac
    }

    /// The equivalent of `espefuse summary --format json`: same keys, same formatting.
    public func summaryJSON() -> Data {
        guard let table else { return Data("{}".utf8) }
        var entries: [(String, [(String, JSONValue)])] = []
        // ESP32-S3: without a calibration block (BLK_VERSION_MAJOR = 0), espefuse hides its fields.
        let hideCalibration = chip == .esp32s3 && raw("BLK_VERSION_MAJOR") == 0
        for definition in table.fields where definition.inSummary && !(hideCalibration && definition.category == "calibration") {
            let field = field(for: definition)
            entries.append((definition.name, summaryEntry(field, start: definition.bits.map(\.start).min(),
                                                          bitCount: shownSize(bitCount: definition.bitCount, type: definition.type,
                                                                              block: definition.block).bitCount)))
        }
        for label in table.composites {
            guard let field = composite(for: label) else { continue }
            entries.append((label.name, summaryEntry(field, start: field.bitRanges.first?.lowerBound,
                                                     bitCount: shownSize(bitCount: label.bitCount, type: label.type, block: label.block).bitCount)))
        }
        return Data(JSONValue.object(entries.sorted { $0.0 < $1.0 }.map { ($0.0, .object($0.1)) }).pythonJSON().utf8)
    }

    // MARK: Internals

    var efuseTable: EfuseTable? { table }
    var isVirtual: Bool { device == nil }
    var connectedDevice: ESPDevice? { device }

    /// Reads the blocks from the chip into `state` (after a hardware burn).
    func reloadFromChip() async throws {
        guard let device, let layout = EfuseLayout.layout(for: chip) else { return }
        state = try await Self.read(layout, chip: chip, from: device)
    }

    /// ESP32 with the 3/4 coding scheme: BLOCK1 to BLOCK3 hold 24 bytes each (192-bit keys).
    var usesThreeQuartersCoding: Bool { chip == .esp32 && raw("CODING_SCHEME") == 1 }

    /// Usable bytes of a block: 24 for BLOCK1 to BLOCK3 under the 3/4 coding scheme.
    func byteCount(ofBlock block: Int) -> Int {
        if usesThreeQuartersCoding && (1...3).contains(block) { return 24 }
        return (state.blocks[safe: block]?.count ?? 0) * 4
    }

    func rawValue(_ definition: EfuseDefinition) -> UInt64 { Self.integer(bits(of: definition)) }

    /// Burns (logical OR) the words into the simulated state.
    func apply(_ changes: [EfuseChange]) {
        for change in changes { state.blocks[change.block][change.word] |= change.after }
    }

    /// Whole read-protected blocks: the chip reads them back as zeros.
    func readProtectedBlocks() -> [Int] {
        guard let table else { return [] }
        return table.fields.filter { $0.bitCount >= 192 && isReadProtected($0) }.map(\.block)
    }

    static func read(_ layout: EfuseLayout, chip: ChipFamily, from device: ESPDevice) async throws -> EfuseSnapshot {
        var blocks: [[UInt32]] = []
        for block in layout.blocks {
            var words: [UInt32] = []
            for index in 0..<block.wordCount {
                words.append(try await device.readRegister(block.address + UInt32(index * 4)))
            }
            blocks.append(words)
        }
        var errors: [UInt32] = []
        for address in layout.errorRegisters { errors.append(try await device.readRegister(address)) }
        let date = try await layout.apbControlDate.asyncMap { try await device.readRegister($0) }
        return EfuseSnapshot(chip: chip, blocks: blocks, errorRegisters: errors, apbControlDate: date)
    }

    /// The field's bits concatenated, least significant first. Under the 3/4 coding scheme a
    /// whole-block field stops at the block's 192 bits.
    private func bits(of definition: EfuseDefinition) -> [Bool] {
        let words = state.blocks[safe: definition.block] ?? []
        var out: [Bool] = []
        for range in definition.bits {
            for bit in range.start..<range.start + range.count {
                let word = bit / 32
                out.append(word < words.count && words[word] >> UInt32(bit % 32) & 1 == 1)
            }
        }
        return out.count > 64 ? Array(out.prefix(byteCount(ofBlock: definition.block) * 8)) : out
    }

    /// Size and type shown for a field: a whole block shrinks to 24 bytes under the 3/4 coding scheme.
    private func shownSize(bitCount: Int, type: String, block: Int) -> (bitCount: Int, type: String) {
        let usable = byteCount(ofBlock: block) * 8
        guard bitCount > usable, type.hasPrefix("bytes") else { return (bitCount, type) }
        return (usable, "bytes:\(usable / 8)")
    }

    private func raw(_ name: String) -> UInt64? {
        table?.definition(named: name).map { Self.integer(bits(of: $0)) }
    }

    private static func integer(_ bits: [Bool]) -> UInt64 {
        bits.prefix(64).enumerated().reduce(0) { $1.element ? $0 | 1 << UInt64($1.offset) : $0 }
    }

    private static func bytes(_ bits: [Bool]) -> Data {
        Data(stride(from: 0, to: bits.count, by: 8).map { start in
            bits[start..<min(start + 8, bits.count)].enumerated().reduce(UInt8(0)) { $1.element ? $0 | 1 << UInt8($1.offset) : $0 }
        })
    }

    func isReadProtected(_ definition: EfuseDefinition) -> Bool {
        guard let bit = definition.readDisableBit, let mask = raw("RD_DIS") else { return false }
        return mask >> UInt64(bit) & 1 == 1
    }

    func isWriteProtected(_ definition: EfuseDefinition) -> Bool {
        guard let bit = definition.writeDisableBit, let mask = raw("WR_DIS") else { return false }
        return mask >> UInt64(bit) & 1 == 1
    }

    private func field(for definition: EfuseDefinition) -> EfuseField {
        let bits = bits(of: definition)
        let value: EfuseValue
        if definition.type == "bool" {
            value = .bool(bits.first ?? false)
        } else if definition.idfName.hasPrefix("KEY_PURPOSE_") {
            value = .keyPurpose(KeyPurpose(rawCode: UInt8(truncatingIfNeeded: Self.integer(bits))))
        } else if definition.type.hasPrefix("bytes") {
            let data = Self.bytes(bits)
            let mac = definition.category == "MAC" ? MACAddress(bytes: data) : nil
            value = mac.map(EfuseValue.mac) ?? .bytes(data)
        } else {
            value = .uint(Self.integer(bits))
        }
        return EfuseField(name: EfuseFieldName(definition.name), category: definition.category,
                          description: definition.description, block: definition.block,
                          bitRanges: definition.bits.map { $0.start..<$0.start + $0.count }, value: value,
                          displayValue: presentation(of: definition, value: value, bits: bits).text,
                          isReadProtected: isReadProtected(definition), isWriteProtected: isWriteProtected(definition),
                          type: shownSize(bitCount: definition.bitCount, type: definition.type, block: definition.block).type)
    }

    /// Fields espefuse computes from other fields.
    private func composite(for label: CompositeLabel) -> EfuseField? {
        let value: EfuseValue
        var ranges: [Range<Int>] = []
        var protection: EfuseDefinition?
        switch (chip, label.name) {
        case (.esp32, "PKG_VERSION"):
            value = .uint((raw("CHIP_PACKAGE") ?? 0) | (raw("CHIP_PACKAGE_4BIT") ?? 0) << 3)
        case (.esp32, "WAFER_VERSION_MAJOR"):
            // Revision 0, 1, then 2 or 3 depending on bit 31 of APB_CTRL_DATE.
            let major: UInt64 = raw("CHIP_VER_REV1") == 0 ? 0
                : raw("CHIP_VER_REV2") == 0 ? 1 : ((state.apbControlDate ?? 0) >> 31 & 1 == 1 ? 3 : 2)
            value = .uint(major)
        case (.esp32, "CUSTOM_MAC"):
            guard let definition = table?.definition(named: "MAC_CUSTOM") else { return nil }
            let data = Self.bytes(bits(of: definition))
            value = MACAddress(bytes: data).map(EfuseValue.mac) ?? .bytes(data)
            ranges = definition.bits.map { $0.start..<$0.start + $0.count }
            protection = definition
        case (.esp32, "BLOCK3"):
            let words = (state.blocks[safe: 3] ?? []).prefix(byteCount(ofBlock: 3) / 4)
            value = .bytes(Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(8 * $0)) } }))
            ranges = [0..<byteCount(ofBlock: 3) * 8]
            protection = table?.definition(named: "MAC_CUSTOM")
        case (.esp32s3, "WAFER_VERSION_MINOR"):
            value = .uint((raw("WAFER_VERSION_MINOR_LO") ?? 0) | (raw("WAFER_VERSION_MINOR_HI") ?? 0) << 3)
        case (.esp32s3, "PSRAM_CAPACITY"):
            value = .uint((raw("PSRAM_CAP") ?? 0) | (raw("PSRAM_CAP_3") ?? 0) << 2)
        default:
            return nil
        }
        let text: String
        switch value {
        case .mac(let mac): text = macPresentation(mac, crcField: label.name == "CUSTOM_MAC" ? "CUSTOM_MAC_CRC" : nil, custom: true)
        case .bytes(let data): text = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        case .uint(let number): text = String(number)
        default: text = ""
        }
        return EfuseField(name: EfuseFieldName(label.name), category: label.category, description: label.description,
                          block: label.block, bitRanges: ranges, value: value, displayValue: text,
                          isReadProtected: protection.map(isReadProtected) ?? false,
                          isWriteProtected: protection.map(isWriteProtected) ?? false,
                          type: shownSize(bitCount: label.bitCount, type: label.type, block: label.block).type)
    }

    // MARK: Presentation (aligned with espefuse)

    private func presentation(of definition: EfuseDefinition, value: EfuseValue, bits: [Bool]) -> JSONValue {
        if let converted = calibration(definition, bits: bits) { return converted }
        switch value {
        case .bool(let flag):
            if let name = definition.values[flag ? 1 : 0] { return .string(name) }
            return .bool(flag)
        case .keyPurpose(let purpose):
            return Self.purposeNames[Int(purpose.rawCode)].map { .string($0) } ?? .int(Int64(purpose.rawCode))
        case .mac(let mac):
            return .string(macPresentation(mac, crcField: chip == .esp32 && definition.name == "MAC" ? "MAC_CRC" : nil))
        case .bytes(let data):
            // Like espefuse: a read-protected block is shown as "??".
            if isReadProtected(definition) { return .string(Array(repeating: "??", count: data.count).joined(separator: " ")) }
            return .string(data.map { String(format: "%02x", $0) }.joined(separator: " "))
        case .uint(let number):
            if let name = definition.values[number] { return .string(name) }
            return .int(Int64(truncatingIfNeeded: number))
        }
    }

    /// ESP32: the MAC carries a CRC-8 (Dallas/Maxim); other chips have none. espefuse words a
    /// bad CRC differently for the factory MAC and the custom one.
    private func macPresentation(_ mac: MACAddress, crcField: String?, custom: Bool = false) -> String {
        let text = mac.bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        guard let crcField, let stored = raw(crcField) else { return text + " (OK)" }
        let computed = Self.crc8(mac.bytes)
        if computed == UInt8(stored) { return text + String(format: " (CRC 0x%02x OK)", computed) }
        return custom
            ? text + String(format: " (CRC 0x%02x invalid - calculated 0x%02x)", UInt8(stored), computed)
            : text + String(format: " (CRC 0x%02x has bad CRC, expected 0x%02x)", UInt8(stored), computed)
    }

    /// Calibration conversions established on the ESP32 and ESP32-S3: sign-magnitude (top bit
    /// = sign), times 4 on the S3; ESP32 ADC reference: 1,100 mV + 7 mV per step.
    private func calibration(_ definition: EfuseDefinition, bits: [Bool]) -> JSONValue? {
        guard definition.type.hasPrefix("uint"), (1...32).contains(bits.count) else { return nil }
        let raw = Self.integer(bits)
        let magnitude = Int64(raw & (1 << UInt64(bits.count - 1) - 1))
        let signed = bits.last == true ? -magnitude : magnitude
        switch chip {
        case .esp32 where definition.name == "ADC_VREF":
            return .int(signed * 7 + 1100)
        case .esp32s3 where definition.category == "calibration":
            switch definition.name {
            case "OCODE": return .int(Int64(raw))
            case "TEMP_CALIB": return .double(Double(signed) / 10)
            default: return .int(signed * 4)
            }
        default:
            return nil
        }
    }

    private func summaryEntry(_ field: EfuseField, start: Int?, bitCount: Int) -> [(String, JSONValue)] {
        let value: JSONValue
        if let definition = table?.definition(named: field.name.rawValue) {
            value = presentation(of: definition, value: field.value, bits: bits(of: definition))
        } else if case .uint(let number) = field.value {
            value = .int(Int64(number))
        } else {
            value = .string(field.displayValue)
        }
        return [("bit_len", .int(Int64(bitCount))), ("block", .int(Int64(field.block))),
                ("category", .string(field.category)), ("description", .string(field.description)),
                ("efuse_type", .string(field.type)), ("name", .string(field.name.rawValue)),
                ("pos", start.map { .int(Int64($0 % 32)) } ?? .null), ("readable", .bool(!field.isReadProtected)),
                ("value", value), ("word", start.map { .int(Int64($0 / 32)) } ?? .null),
                ("writeable", .bool(!field.isWriteProtected))]
    }

    /// Key purpose names (ESP-IDF's `esp_efuse_purpose_t` enumeration).
    private static let purposeNames: [Int: String] = [
        0: "USER", 1: "RESERVED", 2: "XTS_AES_256_KEY_1", 3: "XTS_AES_256_KEY_2", 4: "XTS_AES_128_KEY",
        5: "HMAC_DOWN_ALL", 6: "HMAC_DOWN_JTAG", 7: "HMAC_DOWN_DIGITAL_SIGNATURE", 8: "HMAC_UP",
        9: "SECURE_BOOT_DIGEST0", 10: "SECURE_BOOT_DIGEST1", 11: "SECURE_BOOT_DIGEST2",
    ]

    /// CRC-8 Dallas/Maxim (reflected polynomial 0x8C, initial value 0).
    static func crc8(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 1 != 0 ? crc >> 1 ^ 0x8C : crc >> 1 }
        }
        return crc
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self {
        case .some(let value): try await transform(value)
        case .none: nil
        }
    }
}
