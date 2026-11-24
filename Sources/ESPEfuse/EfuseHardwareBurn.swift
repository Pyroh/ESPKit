// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPDevice
import ESPTargets

/// ESP32 eFuse controller registers used to program (ESP-IDF `efuse_reg.h` / `efuse_struct.h`,
/// base `DR_REG_EFUSE_BASE`).
enum ESP32EfuseRegisters {
    static let base: UInt32 = 0x3FF5_A000
    /// First WDATA register of each block (BLOCK0: 7 words, BLOCK1 to BLOCK3: 8 words).
    static let writeData: [(address: UInt32, words: Int)] = [(base + 0x1C, 7), (base + 0x98, 8), (base + 0xB8, 8), (base + 0xD8, 8)]
    static let clock = base + 0xF8               // CLK_SEL0 [7:0], CLK_SEL1 [15:8]
    static let configuration = base + 0xFC       // OP_CODE [15:0]
    static let command = base + 0x104            // READ_CMD bit 0, PGM_CMD bit 1
    static let dacConfiguration = base + 0x118   // DAC_CLK_DIV [7:0]
    static let writeOpcode: UInt32 = 0x5A5A
    static let readOpcode: UInt32 = 0x5AA5
    /// UART0 clock divider: APB frequency = divider × baud rate.
    static let uart0ClockDivider: UInt32 = 0x3FF4_0014

    /// Programming timing by APB frequency (ESP-IDF `efuse_hal_set_timing`): CLK_SEL0, CLK_SEL1, DAC_CLK_DIV.
    static func timing(apbMHz: Int) -> (sel0: UInt32, sel1: UInt32, dacDivider: UInt32) {
        if apbMHz <= 26 { return (250, 255, 52) }
        if apbMHz <= 40 { return (160, 255, 80) }
        return (80, 128, 100)
    }
}

extension EfuseController {
    /// Hardware burn, ESP32 only: one PGM command per block, BLOCK3 down to BLOCK0, then the
    /// postponed locking bits. Each step writes only the new bits, and is followed by a full
    /// read-back: an unrequested bit stops everything (`EfuseError.unexpectedBits`), a requested
    /// bit that did not take is retried twice before `EfuseError.verificationFailed`.
    func burnOnChip(_ compiled: CompiledPlan, postponing: Bool, device: ESPDevice) async throws -> EfuseBurnReport {
        guard chip == .esp32 else {
            throw EfuseError.hardwareBurn("burning a real \(chip) is not available yet (ESP32 only); use EfuseController(virtual:)")
        }
        guard !usesThreeQuartersCoding else {
            throw EfuseError.hardwareBurn("burning a real ESP32 with the 3/4 coding scheme is not available yet")
        }
        try await setProgrammingTiming(device)

        let postponed = postponing ? compiled.lockingMask : [:]
        var steps: [EfuseBurnReport.Step] = []
        for block in compiled.target.indices.reversed() {
            var wanted = compiled.target[block]
            if block == 0 {
                for (word, mask) in postponed { wanted[word] &= ~mask | state.blocks[0][word] }
            }
            if let step = try await programStep(block: block, wanted: wanted, postponed: false, device: device) {
                steps.append(step)
            }
        }
        if !postponed.isEmpty,
           let step = try await programStep(block: 0, wanted: compiled.target[0], postponed: true, device: device) {
            steps.append(step)
        }
        return EfuseBurnReport(steps: steps)
    }

    /// Programs the bits of `wanted` that are still 0 in `block`, then checks every block.
    private func programStep(block: Int, wanted: [UInt32], postponed: Bool,
                             device: ESPDevice) async throws -> EfuseBurnReport.Step? {
        let before = state.blocks
        let changes = wanted.indices.compactMap { word -> EfuseChange? in
            let current = before[block][word]
            let after = current | wanted[word]
            return after == current ? nil : EfuseChange(block: block, word: word, before: current, after: after)
        }
        guard !changes.isEmpty else { return nil }
        // Blocks this step makes unreadable (RD_DIS in BLOCK0) read back as zeros afterwards.
        let hiddenBefore = Set(readProtectedBlocks())

        for attempt in 1...3 {
            var words = Array(repeating: UInt32(0), count: ESP32EfuseRegisters.writeData[block].words)
            for change in changes { words[change.word] = change.newBits & ~state.blocks[block][change.word] }
            try await program(block: block, words: words, device: device)
            try await reloadFromChip()

            let hidden = Set(readProtectedBlocks()).subtracting(hiddenBefore)
            var missing = false
            for index in state.blocks.indices where !hidden.contains(index) && !hiddenBefore.contains(index) {
                for word in state.blocks[index].indices {
                    let allowed = before[index][word] | (index == block ? wanted[word] : 0)
                    let unexpected = state.blocks[index][word] & ~allowed
                    if unexpected != 0 { throw EfuseError.unexpectedBits(block: index, word: word, bits: unexpected) }
                    if index == block && state.blocks[index][word] & wanted[word] != wanted[word] { missing = true }
                }
            }
            if !missing || hidden.contains(block) { break }
            if attempt == 3 { throw EfuseError.verificationFailed(block: block) }
        }
        return .init(block: block, changes: changes, postponed: postponed)
    }

    /// Clears every WDATA register, loads this block's words, programs, then reloads the read registers.
    private func program(block: Int, words: [UInt32], device: ESPDevice) async throws {
        typealias R = ESP32EfuseRegisters
        for (address, count) in R.writeData {
            for word in 0..<count { try await device.writeRegister(address + UInt32(word * 4), 0) }
        }
        for (word, value) in words.enumerated() where value != 0 {
            try await device.writeRegister(R.writeData[block].address + UInt32(word * 4), value)
        }
        try await run(R.writeOpcode, command: 0x2, device: device)
        try await run(R.readOpcode, command: 0x1, device: device)
        for word in words.indices { try await device.writeRegister(R.writeData[block].address + UInt32(word * 4), 0) }
    }

    private func run(_ opcode: UInt32, command: UInt32, device: ESPDevice) async throws {
        try await device.writeRegister(ESP32EfuseRegisters.configuration, opcode, mask: 0xFFFF)
        try await device.writeRegister(ESP32EfuseRegisters.command, command)
        for _ in 0..<100 {
            if try await device.readRegister(ESP32EfuseRegisters.command) & 0x3 == 0 { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw EfuseError.hardwareBurn("the eFuse controller did not finish its \(command == 0x2 ? "program" : "read") command")
    }

    /// Timing from the APB frequency, measured as the UART0 divider times the current baud rate.
    private func setProgrammingTiming(_ device: ESPDevice) async throws {
        let divider = try await device.readRegister(ESP32EfuseRegisters.uart0ClockDivider) & 0xF_FFFF
        let apbMHz = Int((Double(divider) * Double(await device.baudRate) / 1_000_000).rounded())
        guard (20...81).contains(apbMHz) else {
            throw EfuseError.hardwareBurn("APB frequency measured at \(apbMHz) MHz; refusing to set the eFuse timing")
        }
        let timing = ESP32EfuseRegisters.timing(apbMHz: apbMHz)
        try await device.writeRegister(ESP32EfuseRegisters.dacConfiguration, timing.dacDivider, mask: 0xFF)
        try await device.writeRegister(ESP32EfuseRegisters.clock, timing.sel0 | timing.sel1 << 8, mask: 0xFFFF)
    }
}
