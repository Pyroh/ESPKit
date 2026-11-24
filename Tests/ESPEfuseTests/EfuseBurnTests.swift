// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPSecure
import ESPTargets
@testable import ESPEfuse

private func issues(_ controller: EfuseController, _ plan: EfuseBurnPlan) async -> [EfusePlanIssue] {
    do { _ = try await controller.preview(plan); return [] } catch EfuseError.planInvalid(let found) { return found } catch { return [] }
}

@Suite("Programmation des eFuses (virtuel)")
struct EfuseBurnTests {
    @Test func previewDoesNotBurn() async throws {
        let controller = EfuseController(virtual: .esp32s3)
        var plan = EfuseBurnPlan()
        plan.set(EfuseFieldName.ESP32S3.spiBootCryptCnt, to: .uint(1))
        let changes = try await controller.preview(plan)
        #expect(changes.count == 1 && changes[0].block == 0 && changes[0].newBits == 1 << 18)
        #expect(await controller.field("SPI_BOOT_CRYPT_CNT")?.value == .uint(0))
    }

    @Test func refusesInvalidPlans() async throws {
        let controller = EfuseController(virtual: .esp32s3)
        var setup = EfuseBurnPlan()
        setup.set(EfuseFieldName.ESP32S3.spiBootCryptCnt, to: .uint(3))
        setup.writeProtect("DIS_USB_JTAG")
        setup.writeKey(Data(repeating: 7, count: 32), to: .key2, purpose: .hmacUp)
        _ = try await controller.burn(setup, confirm: .irreversible)

        var plan = EfuseBurnPlan()
        plan.set(EfuseFieldName.ESP32S3.spiBootCryptCnt, to: .uint(1))      // 3 → 1 : bit à remettre à 0
        plan.set("DIS_USB_JTAG", to: .bool(true))                            // protégé en écriture
        plan.set("NOT_A_FIELD", to: .uint(1))                               // inconnu
        plan.set("KEY_PURPOSE_3", to: .uint(99))                            // trop large (4 bits)
        plan.writeKey(Data(count: 16), to: .key3, purpose: .user)           // longueur
        plan.writeKey(Data(repeating: 1, count: 32), to: .key2, purpose: .user)   // bloc déjà utilisé
        plan.writeKey(Data(repeating: 1, count: 32), to: .flashEncryption, purpose: .user)   // pas sur S3
        plan.burnBits([256], in: 4)                                         // hors du bloc
        plan.readProtect("DIS_ICACHE")                                      // pas de bit RD_DIS
        let found = await issues(controller, plan)
        #expect(Set(found.map(\.operation)) == Set(0..<9), "\(found)")
        // Rien n'a été brûlé.
        await #expect(throws: EfuseError.self) { _ = try await controller.burn(plan, confirm: .irreversible) }
        #expect(await controller.field("SPI_BOOT_CRYPT_CNT")?.value == .uint(3))
    }

    @Test func burnsFromTheLastBlockAndPostponesLockingBits() async throws {
        let controller = EfuseController(virtual: .esp32s3)
        var plan = EfuseBurnPlan()
        plan.set(EfuseFieldName.ESP32S3.disDownloadMode, to: .bool(true))
        plan.writeKey(Data(0..<32), to: .key0, purpose: .xtsAES128Key)
        plan.writeBlockData(Data([1, 2, 3]), to: 3)
        let report = try await controller.burn(plan, confirm: .irreversible)
        #expect(report.steps.map(\.block) == [4, 3, 0, 0])
        #expect(report.steps.last?.postponed == true)
        #expect(report.steps.last?.changes.first?.newBits == 1)                // DIS_DOWNLOAD_MODE, bit 128
        // La clé XTS est protégée en lecture : relue à zéro, affichée « ?? ».
        let key = try #require(await controller.field("BLOCK_KEY0"))
        #expect(key.isReadProtected && key.isWriteProtected)
        #expect(key.value == .bytes(Data(count: 32)))
        #expect(key.displayValue.hasPrefix("?? ??"))
        #expect(await controller.field("KEY_PURPOSE_0")?.value == .keyPurpose(.xtsAES128Key))
    }

    @Test func writesSecureBootDigestsInClear() async throws {
        let key = try SecureBootV2.SigningKey.generate(.ecdsa256)
        let controller = EfuseController(virtual: .esp32s3)
        var plan = EfuseBurnPlan()
        plan.writeKeyDigest(key.publicKey, to: .key1, purpose: .secureBootDigest0)
        _ = try await controller.burn(plan, confirm: .irreversible)
        #expect(await controller.field("BLOCK_KEY1")?.value == .bytes(key.publicKey.digest))
        #expect(await controller.field("BLOCK_KEY1")?.isReadProtected == false)

        var wrong = EfuseBurnPlan()
        wrong.writeKeyDigest(key.publicKey, to: .key2, purpose: .xtsAES128Key)
        #expect(!(await issues(controller, wrong)).isEmpty)
    }

    @Test func tokensAreReadOnly() async throws {
        let token = await EfuseController(virtual: .esp32s3).token()
        let controller = try EfuseController(token: token)
        await #expect(throws: EfuseError.readOnly) { _ = try await controller.burn(EfuseBurnPlan(), confirm: .irreversible) }
    }

    @Test(arguments: [
        (Data(0..<32), "a04c470d3ffcb203dae9f413"),
        (Data(count: 32), "000000000000000000000000"),
        (Data(repeating: 0xFF, count: 32), "13a36292597404257375e0aa"),
    ])
    func reedSolomonParityMatchesReference(data: Data, expected: String) {
        // Références : reedsolo 1.7.0, RSCodec(12), paramètres par défaut.
        #expect(ReedSolomon.parity(for: data).map { String(format: "%02x", $0) }.joined() == expected)
    }
}
