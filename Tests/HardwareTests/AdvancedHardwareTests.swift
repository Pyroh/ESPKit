// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPImage
import ESPKit

// Phase 6 on real boards, same variables as HardwareTests. Nothing here touches the eFuses.
// The scratch flash areas (0x300000 and up) are erased at the end of each test.
// runFlashApplication also needs ESPKIT_FIRMWARE_ESP32 / ESPKIT_FIRMWARE_S3 (flashed first).

private let environment = ProcessInfo.processInfo.environment
private let boards: [(chip: ChipFamily, port: String?, firmware: String?)] = [
    (.esp32, environment["ESPKIT_PORT_ESP32"], environment["ESPKIT_FIRMWARE_ESP32"]),
    (.esp32s3, environment["ESPKIT_PORT_S3"], environment["ESPKIT_FIRMWARE_S3"]),
]
private let anyBoard = boards.contains { $0.port != nil }
private let scratch: UInt32 = 0x30_0000

private func connectOptions(_ chip: ChipFamily, stub: Bool = true) -> ConnectOptions {
    var options = ConnectOptions()
    options.expectedChip = chip
    if !stub {
        options.stub = .romOnly
        options.baudRate = nil
    }
    return options
}

private func random(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
}

/// Serial port that outlives the session: `close()` does nothing, so the test can read what
/// the chip prints after `loadRAMAndRun` or `runFlashApplication` without a reset.
private struct KeptOpenPort: Transport {
    let port: SerialPort
    var usbIdentity: USBIdentity? { port.usbIdentity }
    func open() async throws { try await port.open() }
    func close() async {}
    func write(_ data: Data) async throws { try await port.write(data) }
    func read(maxCount: Int, timeout: Duration) async throws -> Data { try await port.read(maxCount: maxCount, timeout: timeout) }
    func discardInput() async throws { try await port.discardInput() }
    func setBaudRate(_ rate: Int) async throws { try await port.setBaudRate(rate) }
    func setControlLines(dtr: Bool?, rts: Bool?) async throws { try await port.setControlLines(dtr: dtr, rts: rts) }
}

/// Reads `port` until `marker` shows up or `timeout` expires.
private func read(_ port: SerialPort, until marker: Data, timeout: Duration) async -> Data {
    let deadline = ContinuousClock.now + timeout
    var received = Data()
    while ContinuousClock.now < deadline, received.range(of: marker) == nil {
        guard let chunk = try? await port.read(maxCount: 1024, timeout: .milliseconds(200)) else { break }
        received.append(chunk)
    }
    return received
}

extension Boards {
    @Suite("Hardware: phase 6", .serialized, .enabled(if: anyBoard))
    struct AdvancedHardwareTests {
        @Test("Flash status, SFDP and memory", arguments: boards.filter { $0.port != nil }.map(\.chip))
        func statusSFDPAndMemory(chip: ChipFamily) async throws {
            let port = try #require(boards.first { $0.chip == chip }?.port)
            let esp = try await ESPDevice.connect(port: port, options: connectOptions(chip))
            let status = try await esp.readFlashStatus(byteCount: 2)
            // Writing the same value back (volatile): exercises the sequence without changing the flash.
            try await esp.writeFlashStatus(status, byteCount: 2)
            #expect(try await esp.readFlashStatus(byteCount: 2) == status)

            let header = try await esp.readSFDP(at: 0, count: 16)
            #expect(header.prefix(4) == Data("SFDP".utf8), "SFDP header \(header.map { String(format: "%02x", $0) }.joined())")

            let macWord: UInt32 = chip == .esp32 ? 0x3FF5_A004 : 0x6000_7044
            let memory = try await esp.readMemory(at: macWord, count: 8).value
            #expect(memory.prefix(4) == withUnsafeBytes(of: try await esp.readRegister(macWord).littleEndian) { Data($0) })
            print("\(chip): flash status \(String(status, radix: 16)), SFDP revision \(header[5]).\(header[4]), \(header[6] + 1) parameter header(s)")
            await esp.disconnect(.hard)
        }

        @Test("Differential reflash", arguments: boards.filter { $0.port != nil }.map(\.chip))
        func differentialReflash(chip: ChipFamily) async throws {
            let port = try #require(boards.first { $0.chip == chip }?.port)
            let esp = try await ESPDevice.connect(port: port, options: connectOptions(chip))
            let old = random(0x1_0000)
            let full = try await esp.writeFlash([FlashRegion(address: scratch, data: old)]).value
            var new = old
            new[0x2345] ^= 0xFF
            new[0xA000] ^= 0xFF
            var options = WriteFlashOptions()
            options.previousContents = [FlashRegion(address: scratch, data: old)]
            let diff = try await esp.writeFlash([FlashRegion(address: scratch, data: new)], options: options).value
            let back = try await esp.readFlash(at: scratch, count: new.count).value
            #expect(back == new)
            let fullSent = full.regions[0].bytesSent, diffSent = diff.regions[0].bytesSent
            #expect(diffSent < fullSent / 4, "differential: \(diffSent) B sent, full: \(fullSent) B")
            print("\(chip): full write \(fullSent) B sent in \(full.regions[0].duration), differential \(diffSent) B in \(diff.regions[0].duration)")
            try await esp.eraseRegion(at: scratch, count: 0x1_0000)
            await esp.disconnect(.hard)
        }

        /// Flash encryption is not enabled on the bench boards: the write goes through the hardware
        /// engine with whatever key it holds. On the ESP32 (BLOCK1 blank, FLASH_CRYPT_CONFIG = 0) that
        /// is an all-zero key without tweak, which `FlashEncryption` reproduces.
        @Test("Encrypted write", arguments: boards.filter { $0.port != nil }.map(\.chip))
        func encryptedWrite(chip: ChipFamily) async throws {
            let port = try #require(boards.first { $0.chip == chip }?.port)
            let esp = try await ESPDevice.connect(port: port, options: connectOptions(chip))
            let address = scratch + 0x1_0000
            let plain = random(0x1000)
            var options = WriteFlashOptions()
            await #expect(throws: UsageError.self) {
                try await esp.writeFlash([FlashRegion(address: address, data: plain, encrypt: true)], options: options).value
            }
            options.ignoreEncryptionEfuses = true
            let report = try await esp.writeFlash([FlashRegion(address: address, data: plain, encrypt: true)], options: options).value
            #expect(report.regions[0].md5 == nil)
            let raw = try await esp.readFlash(at: address, count: plain.count).value
            #expect(raw != plain)
            let candidates: [(String, Data)] = chip == .esp32
                ? [("AES-256, zero key, no tweak", try FlashEncryption.encrypt(plain, at: address, key: Data(count: 32), scheme: .esp32(cryptConfig: 0)))]
                : [("XTS-AES-128, zero key", try FlashEncryption.encrypt(plain, at: address, key: Data(count: 32), scheme: .xtsAES128)),
                   ("XTS-AES-256, zero key", try FlashEncryption.encrypt(plain, at: address, key: Data(count: 64), scheme: .xtsAES256))]
            let match = candidates.first { $0.1 == raw }?.0
            print("\(chip): encrypted write \(match.map { "matches \($0)" } ?? "matches no zero-key model")")
            if chip == .esp32 { #expect(match != nil) }
            try await esp.eraseRegion(at: address, count: 0x1000)
            await esp.disconnect(.hard)
        }

        /// The bundled stub is itself a RAM image: once loaded with `loadRAMAndRun`, it says "OHAI".
        @Test("Load and run code in RAM", arguments: boards.filter { $0.port != nil }.map(\.chip))
        func loadRAMAndRun(chip: ChipFamily) async throws {
            let path = try #require(boards.first { $0.chip == chip }?.port)
            let stub = try #require(StubImage.bundled(for: chip))
            let serial = SerialPort(path: path)
            let esp = try await ESPDevice.connect(KeptOpenPort(port: serial), options: connectOptions(chip, stub: false))
            let image = FirmwareImage(chip: chip, entryPoint: stub.entry, flashMode: .dio, flashFrequencyCode: 0, flashSizeCode: 0,
                                      segments: [.init(loadAddress: stub.textAddress, data: stub.text, region: .iram),
                                                 .init(loadAddress: stub.dataAddress, data: stub.data, region: .dram)],
                                      extendedHeader: .init(chipID: chip.imageChipID ?? 0))
            try await esp.loadRAMAndRun(image)
            #expect(await esp.state == .closed)
            let ohai = Data([0xC0]) + Data("OHAI".utf8) + Data([0xC0])
            let received = await read(serial, until: ohai, timeout: .seconds(3))
            #expect(received.range(of: ohai) != nil, "received \(received.prefix(64).map { String(format: "%02x", $0) }.joined())")
            await serial.close()
            // Back to a clean state: a fresh session resets the chip.
            let again = try await ESPDevice.connect(port: path, options: connectOptions(chip, stub: false))
            await again.disconnect(.hard)
        }

        @Test("Run the flash application", arguments: boards.filter { $0.port != nil && $0.firmware != nil }.map(\.chip))
        func runFlashApplication(chip: ChipFamily) async throws {
            let board = try #require(boards.first { $0.chip == chip })
            let path = try #require(board.port), folder = URL(fileURLWithPath: try #require(board.firmware))
            let flasher = try await ESPDevice.connect(port: path, options: connectOptions(chip))
            _ = try await flasher.writeFlash(try firmwareBuild(folder.path)).value
            await flasher.disconnect(.stayInBootloader)

            let serial = SerialPort(path: path)
            let esp = try await ESPDevice.connect(KeptOpenPort(port: serial), options: connectOptions(chip, stub: false))
            try await esp.runFlashApplication()
            let marker = Data("ESPKit HIL OK \(chip.rawValue)".utf8)
            var received = await read(serial, until: marker, timeout: .seconds(5))
            await serial.close()
            if received.range(of: marker) == nil {
                // Over USB-Serial-JTAG the port went away during the reset: open it again.
                let deadline = ContinuousClock.now + .seconds(10)
                while ContinuousClock.now < deadline {
                    let again = SerialPort(path: path)
                    guard (try? await again.open()) != nil else { try await Task.sleep(for: .milliseconds(200)); continue }
                    received += await read(again, until: marker, timeout: deadline - .now)
                    await again.close()
                    break
                }
            }
            #expect(received.range(of: marker) != nil, "console: \(String(decoding: received.suffix(300), as: UTF8.self).debugDescription)")
        }
    }
}
