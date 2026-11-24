// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPDevice
@testable import ESPEfuse

private func connect(_ chip: SimulatedChip) async throws -> (ESPDevice, EfuseController) {
    var options = ConnectOptions()
    options.stub = .romOnly
    options.baudRate = nil
    let esp = try await ESPDevice.connect(chip, options: options)
    return (esp, try await EfuseController(device: esp))
}

@Suite("eFuse burning on a simulated ESP32")
struct EfuseHardwareBurnTests {
    @Test func burnsOneBitWithTheTimingForA40MHzAPB() async throws {
        let chip = SimulatedChip.esp32()
        let (_, controller) = try await connect(chip)
        var plan = EfuseBurnPlan()
        plan.burnBits([255], in: 3)
        let report = try await controller.burn(plan, confirm: .irreversible)
        #expect(report.steps.map(\.block) == [3])
        #expect(await chip.efuses?[3][7] == 0x8000_0000)
        #expect(await chip.efusePrograms == 1)
        #expect(await chip.registers[0x3FF5_A0F8] == 160 | 255 << 8)     // CLK_SEL0, CLK_SEL1
        #expect(await chip.registers[0x3FF5_A118] == 80)                 // DAC_CLK_DIV
        #expect(await controller.blocks()[3].words[7] == 0x8000_0000)
        // Every WDATA register is left at zero.
        for offset in stride(from: UInt32(0x1C), through: 0xF4, by: 4) where offset < 0x38 || offset >= 0x98 {
            #expect(await chip.registers[0x3FF5_A000 + offset] ?? 0 == 0)
        }
    }

    @Test func burnsTheKeyThenItsProtectionsInBlockZero() async throws {
        let chip = SimulatedChip.esp32()
        let (_, controller) = try await connect(chip)
        var plan = EfuseBurnPlan()
        plan.writeKey(Data(0..<32), to: .secureBootV1, purpose: .user)
        let report = try await controller.burn(plan, confirm: .irreversible)
        #expect(report.steps.map(\.block) == [2, 0])
        let fuses = try #require(await chip.efuses)
        #expect(fuses[2][0] == 0x1C1D_1E1F)                              // reversed, like espefuse
        #expect(fuses[0][0] & (1 << 17) != 0)                            // RD_DIS for BLOCK2
        #expect(fuses[0][0] & (1 << 8) != 0)                             // WR_DIS for BLOCK2
        #expect(await controller.blocks()[2].words.allSatisfy { $0 == 0 })   // now unreadable
        #expect(await controller.blocks()[2].isReadProtected)
    }

    @Test func stopsAtTheFirstUnexpectedBit() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setEfuseGlitch(block: 1, word: 0, bits: 0x10)
        let (_, controller) = try await connect(chip)
        var plan = EfuseBurnPlan()
        plan.writeBlockData(Data([1, 2, 3, 4]), to: 3, offset: 24)
        plan.writeProtect("SECURE_VERSION")                               // a BLOCK0 bit, never reached
        await #expect(throws: EfuseError.unexpectedBits(block: 1, word: 0, bits: 0x10)) {
            try await controller.burn(plan, confirm: .irreversible)
        }
        #expect(await chip.efusePrograms == 1)
        #expect(await chip.efuses?[0][0] == 0)
    }

    @Test func retriesABurnThatDidNotTakeThenGivesUp() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setEfuseIgnoredPrograms(1)
        let (_, controller) = try await connect(chip)
        var plan = EfuseBurnPlan()
        plan.burnBits([224], in: 3)
        _ = try await controller.burn(plan, confirm: .irreversible)
        #expect(await chip.efusePrograms == 2)
        #expect(await chip.efuses?[3][7] == 1)

        await chip.setEfuseIgnoredPrograms(3)
        var next = EfuseBurnPlan()
        next.burnBits([225], in: 3)
        await #expect(throws: EfuseError.verificationFailed(block: 3)) { try await controller.burn(next, confirm: .irreversible) }
    }

    @Test func refusesOtherChipsAndTheThreeQuartersScheme() async throws {
        let (_, s3) = try await connect(SimulatedChip.esp32s3())
        var plan = EfuseBurnPlan()
        plan.burnBits([0], in: 3)
        await #expect(throws: EfuseError.self) { try await s3.burn(plan, confirm: .irreversible) }

        let chip = SimulatedChip.esp32()
        await chip.setRegister(0x3FF5_A018, 1)                            // CODING_SCHEME = 3/4
        let (_, esp32) = try await connect(chip)
        await #expect(throws: EfuseError.self) { try await esp32.burn(plan, confirm: .irreversible) }
        #expect(await chip.efusePrograms == 0)
    }
}
