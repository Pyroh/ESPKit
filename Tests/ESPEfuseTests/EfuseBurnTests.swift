// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPSecure
import ESPTargets
@testable import ESPEfuse

private func issues(_ controller: EfuseController, _ plan: EfuseBurnPlan) async -> [EfusePlanIssue] {
    do { _ = try await controller.preview(plan); return [] } catch EfuseError.planInvalid(let found) { return found } catch { return [] }
}

@Suite("eFuse burning (virtual)")
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
        plan.set(EfuseFieldName.ESP32S3.spiBootCryptCnt, to: .uint(1))      // 3 → 1: a bit would go back to 0
        plan.set("DIS_USB_JTAG", to: .bool(true))                            // write-protected
        plan.set("NOT_A_FIELD", to: .uint(1))                               // unknown
        plan.set("KEY_PURPOSE_3", to: .uint(99))                            // too wide (4 bits)
        plan.writeKey(Data(count: 16), to: .key3, purpose: .user)           // length
        plan.writeKey(Data(repeating: 1, count: 32), to: .key2, purpose: .user)   // block already used
        plan.writeKey(Data(repeating: 1, count: 32), to: .flashEncryption, purpose: .user)   // not on the S3
        plan.burnBits([256], in: 4)                                         // outside the block
        plan.readProtect("DIS_ICACHE")                                      // no RD_DIS bit
        let found = await issues(controller, plan)
        #expect(Set(found.map(\.operation)) == Set(0..<9), "\(found)")
        // Nothing was burned.
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
        // The XTS key is read-protected: read back as zeros, shown as "??".
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
        // References: reedsolo 1.7.0, RSCodec(12), default parameters.
        #expect(ReedSolomon.parity(for: data).map { String(format: "%02x", $0) }.joined() == expected)
    }
}

@Suite("ESP32 3/4 coding scheme (virtual)")
struct ThreeQuartersCodingTests {
    private func threeQuartersController() async throws -> EfuseController {
        let controller = EfuseController(virtual: .esp32)
        var coding = EfuseBurnPlan()
        coding.set(EfuseFieldName.ESP32.codingScheme, to: .uint(1))
        _ = try await controller.burn(coding, confirm: .irreversible)
        return controller
    }

    @Test func blocksOneToThreeHold24Bytes() async throws {
        let controller = try await threeQuartersController()
        let blocks = await controller.blocks()
        #expect(blocks.map(\.words.count) == [7, 6, 6, 6])
        #expect(await controller.field("BLOCK2")?.type == "bytes:24")
        // Without 3/4, the same blocks are 32 bytes.
        #expect(await EfuseController(virtual: .esp32).blocks().map(\.words.count) == [7, 8, 8, 8])
    }

    @Test func keysAre192Bits() async throws {
        let controller = try await threeQuartersController()
        var long = EfuseBurnPlan()
        long.writeKey(Data(count: 32), to: .flashEncryption, purpose: .user)
        await #expect(throws: EfuseError.self) { try await controller.preview(long) }
        var key = EfuseBurnPlan()
        key.writeKey(Data(1...24), to: .secureBootV1, purpose: .user, readProtect: false)
        _ = try await controller.burn(key, confirm: .irreversible)
        let stored = try #require(await controller.blocks()[safe: 2]).words
        #expect(stored.first == 0x1516_1718)                 // reversed, like espefuse

        var short = EfuseBurnPlan()
        short.writeKey(Data(count: 24), to: .flashEncryption, purpose: .user)
        await #expect(throws: EfuseError.self) { try await EfuseController(virtual: .esp32).preview(short) }
    }

    @Test func blockDataStopsAt24Bytes() async throws {
        let controller = try await threeQuartersController()
        var plan = EfuseBurnPlan()
        plan.writeBlockData(Data(repeating: 1, count: 8), to: 3, offset: 20)
        await #expect(throws: EfuseError.self) { try await controller.preview(plan) }
        var bits = EfuseBurnPlan()
        bits.burnBits([192], in: 3)
        await #expect(throws: EfuseError.self) { try await controller.preview(bits) }
        var fits = EfuseBurnPlan()
        fits.writeBlockData(Data(repeating: 1, count: 8), to: 3, offset: 16)
        #expect(try await controller.preview(fits).count == 2)
    }
}
