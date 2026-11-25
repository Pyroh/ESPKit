// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPImage
import ESPSupport
import ESPTargets
@testable import ESPDevice

private func options(stub: StubPolicy = .load) -> ConnectOptions {
    var options = ConnectOptions()
    options.stub = stub
    options.baudRate = nil
    return options
}

private func pattern(_ count: Int, seed: UInt8 = 0) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) })
}

@Suite("Memory and execution")
struct MemoryTests {
    @Test func readsMemoryWordByWordAndTrims() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setRegister(0x3FF0_0000, 0x4433_2211)
        await chip.setRegister(0x3FF0_0004, 0x8877_6655)
        await chip.setRegister(0x3FF0_0008, 0xCCBB_AA99)
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        let bytes = try await esp.readMemory(at: 0x3FF0_0000, count: 10).value
        #expect(bytes == Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA]))
        await #expect(throws: UsageError.self) { try await esp.readMemory(at: 0x3FF0_0002, count: 4).value }
    }

    @Test func loadsRAMSegmentsJumpsAndCloses() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        let iram = pattern(0x2000), dram = pattern(100, seed: 3)
        let image = FirmwareImage(chip: .esp32, entryPoint: 0x4008_0400, flashMode: .dio, flashFrequencyCode: 0,
                                  flashSizeCode: 2,
                                  segments: [.init(loadAddress: 0x4008_0000, data: iram, region: .iram),
                                             .init(loadAddress: 0x3FFB_0000, data: dram, region: .dram)],
                                  extendedHeader: .init(chipID: 0))
        try await esp.loadRAMAndRun(image)
        #expect(await chip.memory[0x4008_0000] == iram)
        #expect(await chip.memory[0x3FFB_0000] == dram)
        #expect(await chip.memEndPayloads.last == Data.le(UInt32(0), UInt32(0x4008_0400)))
        #expect(await esp.state == .closed)
        #expect(await chip.isOpen == false)
    }

    @Test func refusesFlashMappedSegments() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options(stub: .romOnly))
        let image = FirmwareImage(chip: .esp32, entryPoint: 0x400D_0000, flashMode: .dio, flashFrequencyCode: 0,
                                  flashSizeCode: 2, segments: [.init(loadAddress: 0x400D_0000, data: pattern(64), region: .irom)],
                                  extendedHeader: .init(chipID: 0))
        await #expect(throws: UsageError.self) { try await esp.loadRAMAndRun(image) }
        #expect(await esp.state == .rom)
    }

    @Test(arguments: [false, true])
    func runsTheFlashApplicationWithAReset(stub: Bool) async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options(stub: stub ? .load : .romOnly))
        let before = await chip.lineChanges.count
        try await esp.runFlashApplication()
        #expect(await chip.lineChanges.count > before)
        #expect(await chip.flashEndPayloads.isEmpty)
        #expect(await esp.state == .closed)
        #expect(await chip.isOpen == false)
    }
}

@Suite("Flash status and SFDP")
struct FlashStatusTests {
    @Test(arguments: [false, true])
    func readsTheStatusRegisters(stub: Bool) async throws {
        let chip = SimulatedChip.esp32s3()
        await chip.setFlashStatus([0x1C, 0x02, 0x60])
        let esp = try await ESPDevice.connect(chip, options: options(stub: stub ? .load : .romOnly))
        #expect(try await esp.readFlashStatus(byteCount: 1) == 0x1C)
        #expect(try await esp.readFlashStatus() == 0x021C)
        #expect(try await esp.readFlashStatus(byteCount: 3) == 0x60_021C)
        await #expect(throws: UsageError.self) { try await esp.readFlashStatus(byteCount: 4) }
    }

    @Test func writesTheStatusInOneWRSRWhenTheFlashAcceptsIt() async throws {
        let chip = SimulatedChip.esp32()
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        try await esp.writeFlashStatus(0x0200)
        #expect(await chip.flashStatus == [0x00, 0x02, 0x00])
        let opcodes = await chip.spiOpcodes
        #expect(opcodes.contains(0x50) && !opcodes.contains(0x06))     // volatile by default
        #expect(!opcodes.contains(0x31))
        #expect(opcodes.last == 0x04)
    }

    @Test func fallsBackToOneWriteRegisterPerByte() async throws {
        let chip = SimulatedChip.esp32()
        await chip.setAcceptsWideStatusWrite(false)
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        try await esp.writeFlashStatus(0x0204, nonVolatile: true)
        #expect(await chip.flashStatus == [0x04, 0x02, 0x00])
        let opcodes = await chip.spiOpcodes
        #expect(opcodes.contains(0x06) && opcodes.contains(0x31))
    }

    @Test func refusesValuesWiderThanTheByteCount() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32(), options: options(stub: .romOnly))
        await #expect(throws: UsageError.self) { try await esp.writeFlashStatus(0x1_0000, byteCount: 2) }
    }

    @Test(arguments: [false, true])
    func readsTheSFDPTable(esp32: Bool) async throws {
        let chip = esp32 ? SimulatedChip.esp32() : SimulatedChip.esp32s3()
        let esp = try await ESPDevice.connect(chip, options: options(stub: .romOnly))
        let table = try await esp.readSFDP(at: 0, count: 14)
        #expect(table == Data(await chip.sfdp.prefix(14)))
        #expect(try await esp.readSFDP(at: 4, count: 2) == Data([0x06, 0x01]))
    }
}

@Suite("Differential reflash")
struct DifferentialFlashTests {
    private static let address: UInt32 = 0x10000

    private func connected(holding old: Data) async throws -> (SimulatedChip, ESPDevice) {
        let chip = SimulatedChip.esp32()
        await chip.setFlash(old, at: Int(Self.address))
        return (chip, try await ESPDevice.connect(chip, options: options()))
    }

    @Test func sendsOnlyTheChangedSectors() async throws {
        let old = pattern(0x5000)
        var new = old
        new[0x2010] ^= 0xFF
        new[0x3FFF] ^= 0xFF                 // same sector, then the next one
        new[0x4000] ^= 0xFF
        let (chip, esp) = try await connected(holding: old)
        var opts = WriteFlashOptions()
        opts.previousContents = [FlashRegion(address: Self.address, data: old)]
        let report = try await esp.writeFlash([FlashRegion(address: Self.address, data: new)], options: opts).value
        let begins = await chip.flashBeginPayloads
        #expect(begins.count == 1)
        #expect(begins.first?.readLE(UInt32.self, at: 0) == 0x3000)
        #expect(begins.first?.readLE(UInt32.self, at: 12) == Self.address + 0x2000)
        #expect(report.regions.first?.skipped == false)
        #expect(await chip.flash.subdata(in: Int(Self.address)..<Int(Self.address) + new.count) == new)
    }

    @Test func treatsMissingOldBytesAsErased() async throws {
        let old = pattern(0x1800)
        let new = old + Data(repeating: 0xFF, count: 0x800) + pattern(0x1000, seed: 9)
        let (chip, esp) = try await connected(holding: old)
        var opts = WriteFlashOptions()
        opts.previousContents = [FlashRegion(address: Self.address, data: old)]
        _ = try await esp.writeFlash([FlashRegion(address: Self.address, data: new)], options: opts).value
        let begins = await chip.flashBeginPayloads
        #expect(begins.map { $0.readLE(UInt32.self, at: 12) } == [Self.address + 0x2000])
    }

    @Test func writesNothingWhenTheContentIsTheSame() async throws {
        let old = pattern(0x3000)
        let (chip, esp) = try await connected(holding: old)
        var opts = WriteFlashOptions()
        opts.previousContents = [FlashRegion(address: Self.address, data: old)]
        let report = try await esp.writeFlash([FlashRegion(address: Self.address, data: old)], options: opts).value
        #expect(await chip.flashBeginPayloads.isEmpty)
        #expect(report.regions.first?.skipped == true)
        #expect(report.regions.first?.bytesSent == 0)
    }

    @Test func writesEverythingWhenTheFlashDoesNotHoldTheOldContent() async throws {
        let old = pattern(0x3000)
        var new = old
        new[0x10] ^= 0xFF
        let (chip, esp) = try await connected(holding: pattern(0x3000, seed: 1))
        var opts = WriteFlashOptions()
        opts.previousContents = [FlashRegion(address: Self.address, data: old)]
        _ = try await esp.writeFlash([FlashRegion(address: Self.address, data: new)], options: opts).value
        let begins = await chip.flashBeginPayloads
        #expect(begins.map { $0.readLE(UInt32.self, at: 0) } == [0x3000])
        #expect(await chip.flash.subdata(in: Int(Self.address)..<Int(Self.address) + new.count) == new)
    }

    @Test func trustedContentSkipsTheCheckAndTheFinalMD5CatchesTheLie() async throws {
        let old = pattern(0x3000)
        var new = old
        new[0x10] ^= 0xFF
        let (_, esp) = try await connected(holding: pattern(0x3000, seed: 1))
        var opts = WriteFlashOptions()
        opts.previousContents = [FlashRegion(address: Self.address, data: old)]
        opts.trustPreviousContents = true
        await #expect(throws: FlashError.self) {
            try await esp.writeFlash([FlashRegion(address: Self.address, data: new)], options: opts).value
        }
    }

    @Test func excludesSkipIfUnchangedAndEncryption() async throws {
        let (_, esp) = try await connected(holding: Data())
        var opts = WriteFlashOptions()
        opts.previousContents = []
        opts.skipIfUnchanged = true
        await #expect(throws: UsageError.self) {
            try await esp.writeFlash([FlashRegion(address: Self.address, data: pattern(16))], options: opts).value
        }
        opts.skipIfUnchanged = false
        await #expect(throws: UsageError.self) {
            try await esp.writeFlash([FlashRegion(address: Self.address, data: pattern(16), encrypt: true)], options: opts).value
        }
    }

    @Test func findsChangedChunksOnAbsoluteSectorBoundaries() {
        let old = Data(repeating: 0, count: 0x3000)
        var new = old
        new[0x0F00] = 1                     // sector 0x10000 for a region starting at 0x10800
        new[0x2900] = 1                     // past the end of the last full sector
        #expect(ESPDevice.changedChunks(old: old, new: new, address: 0x10800) == [0x800..<0x1800, 0x2800..<0x3000])
    }
}

@Suite("Encrypted writes")
struct EncryptedWriteTests {
    @Test func refusedWhenTheEfusesDoNotEnableEncryption() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32s3(), options: options())
        await #expect(throws: UsageError.self) {
            try await esp.writeFlash([FlashRegion(address: 0x20000, data: pattern(64), encrypt: true)]).value
        }
    }

    @Test(arguments: [false, true])
    func sentUncompressedWithTheEncryptWord(stub: Bool) async throws {
        let chip = SimulatedChip.esp32s3()
        let esp = try await ESPDevice.connect(chip, options: options(stub: stub ? .load : .romOnly))
        var opts = WriteFlashOptions()
        opts.ignoreEncryptionEfuses = true
        let plain = pattern(0x1001)
        let report = try await esp.writeFlash([FlashRegion(address: 0x20000, data: plain, encrypt: true),
                                               FlashRegion(address: 0x40000, data: plain)], options: opts).value
        let begins = await chip.flashBeginPayloads
        #expect(begins.first?.count == 20)
        #expect(begins.first?.readLE(UInt32.self, at: 16) == 1)
        #expect(begins.first?.readLE(UInt32.self, at: 0) == 0x1010)          // padded to 16 bytes
        let plainBegin = try #require(begins.last)
        #expect(plainBegin.count == (stub ? 16 : 20))
        if plainBegin.count == 20 { #expect(plainBegin.readLE(UInt32.self, at: 16) == 0) }
        let opcodes = await chip.receivedOpcodes
        #expect(opcodes.contains(Opcode.flashData.rawValue))
        let written = await chip.flash.subdata(in: 0x20000..<0x20000 + plain.count)
        #expect(written == Data(plain.map { $0 ^ SimulatedChip.encryptionMask }))
        #expect(report.regions.first?.md5 == nil)
        #expect(report.regions.last?.md5 != nil)
    }

    @Test func esp32NeedsTheStubAndReadsFlashCryptCnt() async throws {
        let rom = try await ESPDevice.connect(SimulatedChip.esp32(), options: options(stub: .romOnly))
        var opts = WriteFlashOptions()
        opts.ignoreEncryptionEfuses = true
        await #expect(throws: UsageError.self) {
            try await rom.writeFlash([FlashRegion(address: 0x20000, data: pattern(64), encrypt: true)], options: opts).value
        }
        let chip = SimulatedChip.esp32()
        await chip.setRegister(0x3FF5_A000, 1 << 20)          // FLASH_CRYPT_CNT = 1: enabled
        let esp = try await ESPDevice.connect(chip, options: options())
        _ = try await esp.writeFlash([FlashRegion(address: 0x20000, data: pattern(40), encrypt: true)]).value
        #expect(await chip.flashBeginPayloads.last?.readLE(UInt32.self, at: 0) == 64)   // padded to 32 bytes
        await chip.setRegister(0x3FF5_A000, 3 << 20)          // two bits: disabled again
        await #expect(throws: UsageError.self) {
            try await esp.writeFlash([FlashRegion(address: 0x20000, data: pattern(64), encrypt: true)]).value
        }
    }

    @Test func refusesAnUnalignedAddress() async throws {
        let esp = try await ESPDevice.connect(SimulatedChip.esp32s3(), options: options())
        var opts = WriteFlashOptions()
        opts.ignoreEncryptionEfuses = true
        await #expect(throws: UsageError.self) {
            try await esp.writeFlash([FlashRegion(address: 0x20008, data: pattern(64), encrypt: true)], options: opts).value
        }
    }
}
