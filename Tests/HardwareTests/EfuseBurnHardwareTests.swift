// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPKit

// Real eFuse burns. IRREVERSIBLE: only on a sacrificial ESP32, whose port goes in
// ESPKIT_BURN_ESP32 (never set by the other hardware tests). Each test checks the preview
// before burning and only touches bits no ESP-IDF feature uses, so the board keeps working:
//   - the next free bit of BLOCK3 bits 192 to 255 (no field there): repeatable 64 times;
//   - a custom MAC (BLOCK3), once;
//   - a Secure Boot v1 key in BLOCK2 with its read and write protection (BLOCK0), once.
//     Secure Boot itself stays disabled (ABS_DONE_0 is not touched).

private let burnPort = ProcessInfo.processInfo.environment["ESPKIT_BURN_ESP32"]

private func controller() async throws -> (ESPDevice, EfuseController) {
    var options = ConnectOptions()
    options.stub = .romOnly           // 115,200 baud under ROM: the APB measurement is exact
    options.baudRate = nil
    options.expectedChip = .esp32
    let esp = try await ESPDevice.connect(port: try #require(burnPort), options: options)
    return (esp, try await EfuseController(device: esp))
}

extension Boards {
    @Suite("eFuse burning on a sacrificial ESP32", .serialized, .enabled(if: burnPort != nil))
    struct EfuseBurnHardwareTests {
        @Test("Next free bit of BLOCK3")
        func nextFreeBit() async throws {
            let (esp, efuses) = try await controller()
            let words = await efuses.blocks()[3].words
            guard let bit = (192..<256).first(where: { words[$0 / 32] >> UInt32($0 % 32) & 1 == 0 }) else {
                print("ESP32: BLOCK3 bits 192 to 255 are all burned")
                await esp.disconnect(.hard)
                return
            }
            var plan = EfuseBurnPlan()
            plan.burnBits([bit], in: 3)
            let preview = try await efuses.preview(plan)
            try #require(preview.count == 1 && preview[0].block == 3 && preview[0].word == bit / 32
                         && preview[0].newBits == 1 << UInt32(bit % 32), "unexpected preview \(preview)")
            let report = try await efuses.burn(plan, confirm: .irreversible)
            #expect(report.steps.map(\.block) == [3])
            let after = await efuses.blocks()
            #expect(after[3].words[bit / 32] == words[bit / 32] | 1 << UInt32(bit % 32))
            print("ESP32: burned BLOCK3 bit \(bit); BLOCK3 now \(after[3].words.map { String(format: "%08x", $0) }.joined(separator: " "))")
            await esp.disconnect(.hard)
        }

        @Test("Custom MAC in BLOCK3")
        func customMAC() async throws {
            let (esp, efuses) = try await controller()
            if let programmed = await efuses.customMAC() {
                print("ESP32: custom MAC already programmed: \(programmed)")
                await esp.disconnect(.hard)
                return
            }
            let mac = try #require(MACAddress("02:4B:49:54:00:01"))
            var plan = EfuseBurnPlan()
            plan.setCustomMAC(mac)
            let preview = try await efuses.preview(plan)
            try #require(preview.allSatisfy { $0.block == 3 }, "unexpected preview \(preview)")
            _ = try await efuses.burn(plan, confirm: .irreversible)
            #expect(await efuses.customMAC() == mac)
            #expect(await efuses.field("CUSTOM_MAC")?.displayValue.hasSuffix("OK)") == true)
            print("ESP32: custom MAC \(await efuses.field("CUSTOM_MAC")?.displayValue ?? "unreadable")")
            await esp.disconnect(.hard)
        }

        @Test("Secure Boot v1 key in BLOCK2, then its protections in BLOCK0")
        func protectedKey() async throws {
            let (esp, efuses) = try await controller()
            let block2 = await efuses.blocks()[2]
            guard !block2.isReadProtected, block2.words.allSatisfy({ $0 == 0 }) else {
                print("ESP32: BLOCK2 already used (read-protected: \(block2.isReadProtected))")
                await esp.disconnect(.hard)
                return
            }
            var plan = EfuseBurnPlan()
            plan.writeKey(Data((0..<32).map { _ in UInt8.random(in: 0...255) }), to: .secureBootV1, purpose: .user)
            let preview = try await efuses.preview(plan)
            // BLOCK2, and in BLOCK0 only RD_DIS bit 1 (bit 17) and WR_DIS bit 8.
            let blockZero = preview.filter { $0.block == 0 }
            try #require(preview.allSatisfy { $0.block == 2 || $0.block == 0 }
                         && blockZero.count == 1 && blockZero[0].word == 0 && blockZero[0].newBits == 1 << 17 | 1 << 8,
                         "unexpected preview \(preview)")
            let report = try await efuses.burn(plan, confirm: .irreversible)
            #expect(report.steps.map(\.block) == [2, 0])
            let after = await efuses.blocks()[2]
            #expect(after.isReadProtected && after.isWriteProtected)
            #expect(after.words.allSatisfy { $0 == 0 })
            print("ESP32: BLOCK2 key burned, read- and write-protected")
            await esp.disconnect(.hard)
        }
    }
}
