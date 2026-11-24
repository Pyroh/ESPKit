// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPSecure
import ESPTargets
@testable import ESPEfuse

// Burn scenarios compared with espefuse --virt (Tools/oracle/make-burn-references.sh).
// ESPKIT_BURN_REFERENCES names the folder: final-<chip>.json, dump-<chip>.txt, key-ecdsa256.pem.

private let folder = ProcessInfo.processInfo.environment["ESPKIT_BURN_REFERENCES"].map { URL(fileURLWithPath: $0) }

private func s3Plan() throws -> EfuseBurnPlan {
    let pem = try String(contentsOf: folder!.appendingPathComponent("key-ecdsa256.pem"), encoding: .utf8)
    var plan = EfuseBurnPlan()
    plan.writeKey(Data(0..<32), to: .key0, purpose: .xtsAES128Key)
    plan.writeKeyDigest(try SecureBootV2.SigningKey(pemRepresentation: pem).publicKey, to: .key1, purpose: .secureBootDigest0)
    plan.setCustomMAC(MACAddress("02:11:22:33:44:55")!)
    plan.setFlashVoltage(.v3_3)
    plan.writeBlockData(Data(100..<116), to: 9, offset: 4)
    plan.writeProtect("DIS_USB_JTAG")
    plan.burnBits([0, 1, 2, 255], in: 8)
    plan.set(EfuseFieldName.ESP32S3.spiBootCryptCnt, to: .uint(1))
    plan.set(EfuseFieldName.ESP32S3.disDownloadMode, to: .bool(true))
    return plan
}

private func esp32Plan() -> EfuseBurnPlan {
    var plan = EfuseBurnPlan()
    plan.writeKey(Data(0..<32), to: .flashEncryption, purpose: .user)
    plan.setCustomMAC(MACAddress("02:11:22:33:44:55")!)
    plan.setFlashVoltage(.v1_8)
    plan.set(EfuseFieldName.ESP32.flashCryptCnt, to: .uint(1))
    plan.set(EfuseFieldName.ESP32.jtagDisable, to: .bool(true))
    return plan
}

@Suite("Burning compared with espefuse --virt", .enabled(if: folder != nil))
struct EfuseBurnReferenceTests {
    @Test(arguments: [ChipFamily.esp32, .esp32s3])
    func scenarioMatchesEspefuse(chip: ChipFamily) async throws {
        let controller = EfuseController(virtual: chip)
        let report = try await controller.burn(chip == .esp32 ? esp32Plan() : s3Plan(), confirm: .irreversible)
        #expect(report.steps.last?.block == 0)
        let dump = try String(contentsOf: folder!.appendingPathComponent("dump-\(chip.rawValue).txt"), encoding: .utf8)
        #expect(await controller.blocks().map(\.words) == blocks(fromDump: dump))
        let ours = await controller.summaryJSON()
        let theirs = try Data(contentsOf: folder!.appendingPathComponent("final-\(chip.rawValue).json"))
        let issues = differences(ours, theirs)
        #expect(issues.isEmpty, "\(issues.count) difference(s):\n\(issues.prefix(30).joined(separator: "\n"))")
        #expect(ours == theirs)
    }
}
