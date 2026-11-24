// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
import ESPTransport
@testable import ESPDevice

/// Phase 0 options: ROM only, initial baud rate.
private func romOnly() -> ConnectOptions {
    var options = ConnectOptions()
    options.stub = .romOnly
    options.baudRate = nil
    return options
}

@Suite("ESPDevice on a simulated chip")
struct ESPDeviceTests {
    @Test func connectsToESP32ByMagicValue() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: romOnly())
        #expect(esp.chip == .esp32)
        #expect(await esp.state == .rom)
        #expect(await esp.baudRate == 115_200)
        #expect(await chip.baudRate == 115_200)
        #expect(try await esp.macAddress().description == "24:0A:C4:12:34:56")
    }

    @Test func readsESP32FlashIdentityThroughSPIRegisters() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: romOnly())
        let flash = try await esp.flashInfo()
        #expect(flash.manufacturerID == 0xEF)
        #expect(flash.deviceID == 0x4016)
        #expect(flash.jedecID == 0x16_40EF)
        #expect(flash.detectedSize == .mb4)
        // The ESP32 ROM expects 8 bytes for SPI_ATTACH.
        #expect(await chip.attachPayloads == [Data(count: 8)])
        // USR and USR2 are restored after the transaction.
        let writes = await chip.registerWrites
        #expect(writes.last?.address == 0x3FF4_2024)
    }

    @Test func esp32HasNoSecurityInfoNorChipID() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: romOnly())
        await #expect(throws: UsageError.self) { try await esp.securityInfo() }
        await #expect(throws: UsageError.self) { try await esp.chipID() }
    }

    @Test func connectsToESP32S3ByChipIDOverUSBSerialJTAG() async throws {
        let chip = SimulatedChip.esp32s3()
        let esp = try await ESPDevice.connect(chip, options: romOnly())
        #expect(esp.chip == .esp32s3)
        let info = try await esp.securityInfo()
        #expect(info.chipID == 9)
        #expect(info.flags.isEmpty)
        #expect(info.keyPurposes.count == 7)
        #expect(try await esp.macAddress().description == "34:85:C4:12:34:56")
        #expect(try await esp.flashInfo().detectedSize == .mb16)

        // USB-Serial-JTAG sequence: starts with RTS then DTR released, separately.
        let lines = await chip.lineChanges
        #expect(lines.first?.rts == false && lines.first?.dtr == nil)
        // RTC watchdog disabled, super watchdog on auto-feed.
        let writes = await chip.registerWrites
        #expect(writes.contains { $0.address == 0x6000_8098 && $0.value == 0 })
        #expect(writes.contains { $0.address == 0x6000_80B4 && $0.value == 0x8000_0001 })
    }

    @Test func s3OverUARTKeepsWatchdogsAndUsesUnixTightReset() async throws {
        let chip = SimulatedChip.esp32s3(usbSerialJTAG: false)
        _ = try await ESPDevice.connect(chip, options: romOnly())
        #expect(await chip.registerWrites.isEmpty)
        let lines = await chip.lineChanges
        #expect(lines.first?.dtr == false && lines.first?.rts == false)
    }

    @Test func retriesSyncAcrossAttempts() async throws {
        let chip = SimulatedChip.esp32()
        await chip.ignoreSyncs(7)    // 5 SYNCs per attempt: the second attempt is needed
        let esp = try await ESPDevice.connect(chip, options: romOnly())
        #expect(esp.chip == .esp32)
    }

    @Test func reportsNoResponseAfterLastAttempt() async throws {
        let chip = SimulatedChip.esp32()
        await chip.ignoreSyncs(.max)
        var options = romOnly()
        options.connectAttempts = 1
        await #expect(throws: ConnectionError.noResponse(attempts: 1)) {
            try await ESPDevice.connect(chip, options: options)
        }
        #expect(await chip.isOpen == false)
    }

    @Test func rejectsUnexpectedChip() async throws {
        var options = romOnly()
        options.expectedChip = .esp32s3
        await #expect(throws: ConnectionError.chipMismatch(expected: .esp32s3, detected: .esp32)) {
            try await ESPDevice.connect(SimulatedChip.esp32(), options: options)
        }
    }

    @Test func noBundledStubForE22() async throws {
        #expect(StubImage.bundled(for: .esp32e22) == nil)
    }

    @Test func changesBaudRateUnderS3ROM() async throws {
        let chip = SimulatedChip.esp32s3()
        var options = romOnly()
        options.baudRate = 921_600
        let esp = try await ESPDevice.connect(chip, options: options)
        #expect(await esp.baudRate == 921_600)
        #expect(await chip.baudRate == 921_600)
    }

    @Test func refusesBaudChangeUnderESP32ROM() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: romOnly())
        await #expect(throws: UsageError.self) { try await esp.changeBaudRate(921_600) }
    }

    @Test func disconnectResetsAndClosesTheSession() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: romOnly())
        let linesBefore = await chip.lineChanges.count
        await esp.disconnect(.hard)
        #expect(await esp.state == .closed)
        #expect(await chip.isOpen == false)
        let reset = await chip.lineChanges.dropFirst(linesBefore)
        #expect(reset.map(\.rts) == [true, false])
        await #expect(throws: ConnectionError.disconnected) { try await esp.readRegister(0x4000_1000) }
    }

    @Test func concurrentCallsAreSerialized() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: romOnly())
        let values = try await withThrowingTaskGroup(of: UInt32.self) { group in
            for _ in 0..<20 {
                group.addTask { try await esp.readRegister(0x4000_1000) }
                group.addTask { try await esp.readRegister(0x3FF5_A004) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(values.count == 40)
        #expect(values.filter { $0 == 0x00F0_1D83 }.count == 20)
        #expect(values.filter { $0 == 0xC412_3456 }.count == 20)
    }

    @Test func traceCoversResetSyncAndCommands() async throws {
        let (trace, sink) = AsyncStream.makeStream(of: TraceEvent.self)
        var options = romOnly()
        options.trace = sink
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options)
        await esp.disconnect(.stayInBootloader)
        var resets = 0, sent = 0, received = 0
        for await event in trace {
            switch event {
            case .resetStep: resets += 1
            case .sent: sent += 1
            case .received: received += 1
            default: break
            }
        }
        #expect(resets > 0)
        #expect(sent >= 2)        // SYNC, GET_SECURITY_INFO, READ_REG…
        #expect(received >= 2)
    }
}

@Suite("StubImage")
struct StubImageTests {
    @Test func parsesFlasherStubJSON() throws {
        let json = Data("""
        {"entry": 1074521580, "text": "AAECAw==", "text_start": 1074520064,
         "data": "BAU=", "data_start": 1073605544, "bss_start": 1073528832}
        """.utf8)
        let stub = try StubImage(json: json, chip: .esp32, label: "test")
        #expect(stub.text == Data([0, 1, 2, 3]))
        #expect(stub.data == Data([4, 5]))
        #expect(stub.entry == 1_074_521_580)
        #expect(stub.version == .custom("test"))
    }

    @Test func rejectsMalformedImages() {
        #expect(throws: StubError.self) { try StubImage(json: Data("{}".utf8), chip: .esp32) }
        #expect(throws: StubError.self) {
            try StubImage(chip: .esp32, text: Data([1]), textAddress: 0x4000_0002,
                          data: Data(), dataAddress: 0, entry: 0)
        }
        #expect(throws: StubError.self) {
            try StubImage(chip: .esp32, text: Data(count: 16), textAddress: 0x1000,
                          data: Data(count: 16), dataAddress: 0x1008, entry: 0x1000)
        }
    }

    @Test(arguments: ChipFamily.allCases.filter { $0 != .esp32e22 })
    func bundledStubsParse(chip: ChipFamily) throws {
        let stub = try #require(StubImage.bundled(for: chip))
        #expect(stub.chip == chip)
        #expect(stub.version == .bundled("2.0.0"))
        #expect(!stub.text.isEmpty)
        #expect(stub.entry >= stub.textAddress && stub.entry < stub.textAddress + UInt32(stub.text.count))
    }
}
