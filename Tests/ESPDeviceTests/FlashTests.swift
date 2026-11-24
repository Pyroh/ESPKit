// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPImage
import ESPProtocol
import ESPSupport
import ESPTargets
@testable import ESPDevice

private func options(stub: StubPolicy = .load, baudRate: Int? = nil) -> ConnectOptions {
    var options = ConnectOptions()
    options.stub = stub
    options.baudRate = baudRate
    return options
}

/// Données pseudo-aléatoires mais reproductibles, à moitié compressibles.
private func sample(_ count: Int, seed: UInt64 = 1) -> Data {
    var state = seed
    return Data((0..<count).map { index in
        if index % 2 == 0 { return UInt8(truncatingIfNeeded: index / 64) }
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 33)
    })
}

/// Image ESP32-x minimale : en-tête, extension (chip ID), un segment, somme de contrôle, SHA-256.
private func image(chipID: UInt16, payload: Data = sample(200)) -> Data {
    var data = Data([0xE9, 1, 0x00, 0x20])                // magic, 1 segment, QIO, 4 Mo / 40 MHz
    data.appendLE(UInt32(0x4008_0000))                    // entrée
    data.append(contentsOf: [0xEE, 0, 0, 0])              // WP, drv
    data.appendLE(chipID)
    data.append(contentsOf: [0, 0, 0, 0xFF, 0xFF, 0, 0, 0, 0, 1])   // révisions, réservés, append_digest
    data.appendLE(UInt32(0x3FFB_0000))
    data.appendLE(UInt32(payload.count))
    data.append(payload)
    while (data.count + 1) % 16 != 0 { data.append(0) }
    data.append(0xEF)                                     // somme de contrôle (fictive)
    data.append(SHA256.hash(data))
    return data
}

@Suite("Stub")
struct StubLoadingTests {
    @Test func defaultOptionsLoadTheBundledStubAndRaiseTheBaudRate() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip)
        let stub = try #require(StubImage.bundled(for: .esp32))
        #expect(await esp.state == .stub(.bundled("2.0.0")))
        #expect(await chip.memory[stub.textAddress] == stub.text)
        #expect(await chip.memory[stub.dataAddress] == stub.data)
        // Le stub veut le nouveau débit puis l'ancien.
        #expect(await chip.baudPayloads == [Data.le(UInt32(460_800), UInt32(115_200))])
        #expect(await esp.baudRate == 460_800)
        #expect(await chip.baudRate == 460_800)
        // Sous stub, les réponses ont 2 octets d'état : la lecture de registre doit passer.
        #expect(try await esp.macAddress().description == "24:0A:C4:12:34:56")
    }

    @Test func toleratesAMissingMemEndResponse() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setDropMemEndResponse(true)
        let esp = try await ESPDevice.connect(chip, options: options())
        #expect(await esp.stubRunning)
    }

    @Test func reportsAStubThatDoesNotStart() async throws {
        let chip = SimulatedChip.esp32s3()
        await chip.setStubFailsToStart(true)
        await #expect(throws: StubError.failedToStart(.bundled("2.0.0"))) {
            try await ESPDevice.connect(chip, options: options())
        }
    }

    @Test func refusesAStubBuiltForAnotherChip() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options(stub: .romOnly))
        let foreign = try #require(StubImage.bundled(for: .esp32s3))
        await #expect(throws: StubError.chipMismatch(stub: .esp32s3, device: .esp32)) {
            try await esp.loadStub(foreign)
        }
    }

    @Test func stubErrorsUseTheSixteenBitCode() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options())
        // Le stub ne connaît pas READ_FLASH_SLOW : 0xC300 « commande invalide ».
        await #expect(throws: ProtocolError.deviceError(opcode: 0x0E, code: .invalidCommand)) {
            _ = try await esp.channel.execute(Command(.readFlashSlow, payload: .le(UInt32(0), UInt32(64))))
        }
    }
}

@Suite("Écriture flash")
struct WriteFlashTests {
    @Test func writesCompressedRegionsWithTheStub() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let regions = [
            FlashRegion(address: 0x1000, data: image(chipID: 0)),
            FlashRegion(address: 0x8000, data: sample(3_072, seed: 2)),
            FlashRegion(address: 0x1_0000, data: sample(100_001, seed: 3)),
        ]
        let report = try await esp.writeFlash(regions).value
        let flash = await chip.flash
        for region in regions {
            let start = Int(region.address)
            #expect(flash.subdata(in: start..<start + region.data.count) == region.data)
        }
        #expect(report.regions.count == 3)
        #expect(report.regions[2].byteCount == 100_004)                 // aligné sur 4 octets
        #expect(report.regions[2].bytesSent < report.regions[2].byteCount)
        #expect(report.regions.allSatisfy { !$0.skipped && $0.md5 != nil })
        #expect(flash[0x1_0000 + 100_001] == 0xFF)                       // remplissage
        // Le stub n'attend pas le mot « chiffré » de la ROM.
        #expect(await chip.flashBeginPayloads.allSatisfy { $0.count == 16 })
    }

    @Test func writesUncompressedUnderS3ROM() async throws {
        let chip = SimulatedChip.esp32s3()
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        var write = WriteFlashOptions()
        write.compression = .none
        let data = sample(5_000, seed: 4)
        _ = try await esp.writeFlash([FlashRegion(address: 0x2_0000, data: data)], options: write).value
        #expect(await chip.flash.subdata(in: 0x2_0000..<0x2_0000 + 5_000) == data)
        // La ROM de l'S3 attend 5 mots dans FLASH_BEGIN.
        #expect(await chip.flashBeginPayloads.map(\.count) == [20])
        #expect(await chip.flashParamsSize == 16 << 20)
    }

    @Test func writesCompressedUnderESP32ROMAndAlignsOnSectors() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setFlash(Data(repeating: 0x11, count: 0x2000), at: 0x3000)
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        let data = sample(2_000, seed: 5)
        let report = try await esp.writeFlash([FlashRegion(address: 0x3100, data: data)]).value
        let flash = await chip.flash
        #expect(flash.subdata(in: 0x3100..<0x3100 + 2_000) == data)
        #expect(flash.subdata(in: 0x3000..<0x3100) == Data(repeating: 0xFF, count: 0x100))
        #expect(report.regions[0].address == 0x3000)
        #expect(await chip.flashBeginPayloads.map(\.count) == [16])     // ROM ESP32 : 4 mots
    }

    @Test func skipsUnchangedRegions() async throws {
        let chip = SimulatedChip.esp32()
        let data = sample(8_192, seed: 6)
        await chip.setFlash(data, at: 0x4_0000)
        let esp = try await ESPDevice.connect(chip, options: options())
        var write = WriteFlashOptions()
        write.skipIfUnchanged = true
        let report = try await esp.writeFlash([FlashRegion(address: 0x4_0000, data: data)], options: write).value
        #expect(report.regions[0].skipped)
        #expect(await chip.flashBeginPayloads.isEmpty)
    }

    @Test func detectsCorruptedWrites() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        await chip.setCorruptWrites(true)
        await #expect(throws: FlashError.self) {
            _ = try await esp.writeFlash([FlashRegion(address: 0, data: sample(4_096))]).value
        }
    }

    @Test func rejectsInvalidRegions() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options())
        let overlapping = [FlashRegion(address: 0, data: sample(0x2000)), FlashRegion(address: 0x1000, data: sample(16))]
        await #expect(throws: UsageError.self) { _ = try await esp.writeFlash(overlapping).value }
        let tooLarge = [FlashRegion(address: 0x3F_F000, data: sample(0x2000))]
        await #expect(throws: UsageError.self) { _ = try await esp.writeFlash(tooLarge).value }
        await #expect(throws: UsageError.self) { _ = try await esp.writeFlash([FlashRegion(address: 0, data: Data())]).value }
    }

    @Test func refusesAnImageForAnotherChipUnlessForced() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let s3Image = [FlashRegion(address: 0x1_0000, data: image(chipID: 9))]
        await #expect(throws: UsageError.self) { _ = try await esp.writeFlash(s3Image).value }
        var forced = WriteFlashOptions()
        forced.force = true
        _ = try await esp.writeFlash(s3Image, options: forced).value
        #expect(await chip.flash[0x1_0000] == 0xE9)
    }

    @Test func secureBootBlocksLowWritesUnlessForced() async throws {
        let chip = SimulatedChip.esp32s3(flags: 1)          // secureBootEnabled
        let esp = try await ESPDevice.connect(chip, options: options())
        let bootloader = [FlashRegion(address: 0, data: image(chipID: 9))]
        await #expect(throws: UsageError.self) { _ = try await esp.writeFlash(bootloader).value }
        await #expect(throws: UsageError.self) { _ = try await esp.eraseFlash().value }
        var forced = WriteFlashOptions()
        forced.force = true
        _ = try await esp.writeFlash(bootloader, options: forced).value
    }

    @Test func patchesTheBootloaderHeaderAndItsDigest() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let original = image(chipID: 0)
        var write = WriteFlashOptions()
        write.headerOverrides = FlashHeaderOverrides(mode: .set(.dio), frequency: .set(.mhz80), size: .detect)
        let report = try await esp.writeFlash([FlashRegion(address: 0x1000, data: original)], options: write).value
        #expect(report.regions[0].headerPatched)
        let written = await chip.flash.subdata(in: 0x1000..<0x1000 + original.count)
        #expect(written[2] == 0x02)                          // DIO
        #expect(written[3] == 0x2F)                          // 4 Mo, 80 MHz
        let end = try #require(ImageHeader.imageEnd(written))
        #expect(written.subdata(in: end..<end + 32) == SHA256.hash(written.prefix(end)))
        #expect(written.subdata(in: end..<end + 32) != original.subdata(in: end..<end + 32))
    }

    @Test func reportsProgressThenFinishes() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options())
        var finished: WriteFlashReport?
        var sawProgress = false
        for try await event in esp.writeFlash([FlashRegion(address: 0x1_0000, data: sample(70_000))]) {
            switch event {
            case .progress: sawProgress = true
            case .finished(let report): finished = report
            }
        }
        // Contrat : `.finished` arrive toujours ; un consommateur lent peut manquer des progressions.
        #expect(finished?.regions.count == 1)
        #expect(sawProgress)
    }

    @Test func emitsEveryStageInOrder() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options())
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ESPOperationEvent<WriteFlashReport>.self,
                                                                    throwing: (any Error).self)
        _ = try await esp.performWriteFlash([FlashRegion(address: 0x1_0000, data: sample(70_000))],
                                            options: WriteFlashOptions(), sink: ProgressSink(continuation))
        continuation.finish()
        var stages: [OperationProgress.Stage] = []
        var completed: [Int] = []
        for try await case .progress(let progress) in stream {
            stages.append(progress.stage)
            completed.append(progress.completedBytes)
        }
        #expect(stages.first == .preparing)
        #expect(stages.contains(.writing))
        #expect(stages.last == .verifying)
        #expect(completed == completed.sorted())
    }

    @Test func operationsAreCold() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let operation = esp.writeFlash([FlashRegion(address: 0x1_0000, data: sample(1_000))])
        try await Task.sleep(for: .milliseconds(50))
        #expect(await chip.flashBeginPayloads.isEmpty)
        _ = try await operation.value
        _ = try await operation.value                       // chaque parcours relance l'opération
        #expect(await chip.flashBeginPayloads.count == 2)
    }

    @Test func esp8266ROMWritesNeedTheStub() async throws {
        // Sous ROM, ESPKit refuse l'écriture sur ESP8266 sans parler à la puce : on se contente
        // de vérifier la règle sur une session ESP32 forcée en ROM.
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options(stub: .romOnly))
        await #expect(throws: UsageError.self) { _ = try await esp.eraseFlash().value }
        await #expect(throws: UsageError.self) { try await esp.eraseRegion(at: 0, count: 0x1000) }
    }
}

@Suite("Lecture, vérification, effacement")
struct ReadVerifyEraseTests {
    @Test func readsWithTheStubAndAcknowledgements() async throws {
        let chip = SimulatedChip.esp32s3()
        let data = sample(10_000, seed: 7)
        await chip.setFlash(data, at: 0x2000)
        let esp = try await ESPDevice.connect(chip, options: options())
        var reads: [Int] = []
        var result = Data()
        for try await event in esp.readFlash(at: 0x2000, count: 10_000) {
            switch event {
            case .progress(let progress): reads.append(progress.completedBytes)
            case .finished(let value): result = value
            }
        }
        #expect(result == data)
        // Un consommateur lent peut manquer des progressions, jamais les voir reculer.
        #expect(reads == reads.sorted() && reads.allSatisfy { $0 <= 10_000 })
    }

    @Test func recoversFromALostReadPacket() async throws {
        let chip = SimulatedChip.esp32()
        let data = sample(20_000, seed: 14)
        await chip.setFlash(data, at: 0x3_0000)
        let esp = try await ESPDevice.connect(chip, options: options())
        await chip.setDropReadPacket(2)
        #expect(try await esp.readFlash(at: 0x3_0000, count: 20_000).value == data)
        #expect(await chip.dropReadPacket == nil)
        // Deux commandes READ_FLASH : la première interrompue, la seconde à partir du bloc perdu.
        #expect(await chip.receivedOpcodes.filter { $0 == 0xD2 }.count == 2)
    }

    @Test func readsSlowlyUnderROM() async throws {
        let chip = SimulatedChip.esp32()
        let data = sample(300, seed: 8)
        await chip.setFlash(data, at: 0x100)
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        #expect(try await esp.readFlash(at: 0x100, count: 300).value == data)
    }

    @Test func cancelledReadLeavesTheSessionUsable() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let task = Task {
            for try await event in esp.readFlash(at: 0, count: 200_000) {
                if case .progress = event { break }
            }
        }
        _ = try? await task.value
        #expect(try await esp.readRegister(0x4000_1000) == 0x00F0_1D83)
        #expect(try await esp.readFlash(at: 0, count: 64).value == Data(repeating: 0xFF, count: 64))
    }

    @Test func breakingOutOfTheLoopThrowsCancellation() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options())
        let task = Task {
            var iterator = esp.readFlash(at: 0, count: 100_000).makeAsyncIterator()
            _ = try await iterator.next()
            withUnsafeCurrentTask { $0?.cancel() }
            while try await iterator.next() != nil {}
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func verifiesRegions() async throws {
        let chip = SimulatedChip.esp32()
        let good = sample(4_096, seed: 9)
        await chip.setFlash(good, at: 0x1_0000)
        var bad = sample(4_096, seed: 10)
        await chip.setFlash(bad, at: 0x2_0000)
        bad[100] ^= 0x55
        let esp = try await ESPDevice.connect(chip, options: options())
        let results = try await esp.verifyFlash([FlashRegion(address: 0x1_0000, data: good),
                                                 FlashRegion(address: 0x2_0000, data: bad)]).value
        #expect(results[0] == .match(address: 0x1_0000))
        guard case .mismatch(let address, let differences) = results[1] else {
            Issue.record("la deuxième région devrait différer")
            return
        }
        #expect(address == 0x2_0000)
        #expect(differences.map(\.offset) == [100])
    }

    @Test func flashMD5UnderROMDecodesHex() async throws {
        let chip = SimulatedChip.esp32()
        let data = sample(1_024, seed: 11)
        await chip.setFlash(data, at: 0)
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        #expect(try await esp.flashMD5(at: 0, count: 1_024).bytes == MD5.hash(data))
    }

    @Test func erasesWithTheStub() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setFlash(sample(0x3000), at: 0x1_0000)
        let esp = try await ESPDevice.connect(chip, options: options())
        try await esp.eraseRegion(at: 0x1_1000, count: 0x1000)
        var flash = await chip.flash
        #expect(flash.subdata(in: 0x1_1000..<0x1_2000) == Data(repeating: 0xFF, count: 0x1000))
        #expect(flash[0x1_0001] != 0xFF || flash[0x1_0003] != 0xFF)
        await #expect(throws: UsageError.self) { try await esp.eraseRegion(at: 0x10, count: 0x1000) }

        for try await _ in esp.eraseFlash().progress {}
        flash = await chip.flash
        #expect(flash.allSatisfy { $0 == 0xFF })
        #expect(await chip.chipErases == 1)
    }

    @Test func operationsFromSeveralTasksAreSerialized() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options())
        let a = sample(20_000, seed: 12), b = sample(20_000, seed: 13)
        async let first = esp.writeFlash([FlashRegion(address: 0x1_0000, data: a)]).value
        async let second = esp.writeFlash([FlashRegion(address: 0x2_0000, data: b)]).value
        async let mac = esp.macAddress()
        _ = try await (first, second, mac)
        let flash = await chip.flash
        #expect(flash.subdata(in: 0x1_0000..<0x1_0000 + 20_000) == a)
        #expect(flash.subdata(in: 0x2_0000..<0x2_0000 + 20_000) == b)
    }
}
