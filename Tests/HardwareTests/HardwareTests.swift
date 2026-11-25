// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPKit

// Tests on real boards. Skipped until the environment variables are set:
//
//   ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
//
// Phase 0 milestone: detection, MAC and flash identity on the ESP32 and ESP32-S3, in ROM.
//
// Phase 1 milestone: flash a real PlatformIO build (bootloader, partitions, application) with
// the stub, read it back, then check that it boots. The build folder is given by variable:
//
//   ESPKIT_FIRMWARE_ESP32=…/.pio/build/esp32 ESPKIT_FIRMWARE_S3=…/.pio/build/esp32s3
//
// The application must print "ESPKit HIL OK <chip>" on its console (see README).

private let environment = ProcessInfo.processInfo.environment
private let esp32Port = environment["ESPKIT_PORT_ESP32"]
private let s3Port = environment["ESPKIT_PORT_S3"]
private let esp32Firmware = environment["ESPKIT_FIRMWARE_ESP32"]
private let s3Firmware = environment["ESPKIT_FIRMWARE_S3"]

private func romOnly(expecting chip: ChipFamily) -> ConnectOptions {
    var options = ConnectOptions()
    options.stub = .romOnly
    options.baudRate = nil
    options.expectedChip = chip
    return options
}

/// Parent of every hardware suite: `.serialized` then also applies across them, so two tests
/// never open the same serial port at the same time.
@Suite("Boards", .serialized)
enum Boards {}

extension Boards {
    @Suite("Hardware", .serialized)
    struct HardwareTests {
        @Test("ESP32: detection, MAC, flash", .enabled(if: esp32Port != nil))
        func esp32Identity() async throws {
            let esp = try await ESPDevice.connect(port: try #require(esp32Port), options: romOnly(expecting: .esp32))
            #expect(esp.chip == .esp32)
            #expect(await esp.state == .rom)

            let mac = try await esp.macAddress()
            #expect(mac.bytes != Data(count: 6))

            let flash = try await esp.flashInfo()
            #expect(flash.detectedSize != nil, "JEDEC ID \(String(flash.jedecID, radix: 16))")

            await #expect(throws: UsageError.self) { try await esp.chipID() }
            print("ESP32: MAC \(mac), flash \(String(flash.jedecID, radix: 16)) \(flash.detectedSize.map(String.init(describing:)) ?? "?")")
            await esp.disconnect(.hard)
        }

        @Test("ESP32-S3: detection, security, MAC, flash", .enabled(if: s3Port != nil))
        func s3Identity() async throws {
            let esp = try await ESPDevice.connect(port: try #require(s3Port), options: romOnly(expecting: .esp32s3))
            #expect(esp.chip == .esp32s3)

            let security = try await esp.securityInfo()
            #expect(security.chipID == 9)

            let mac = try await esp.macAddress()
            #expect(mac.bytes != Data(count: 6))

            let flash = try await esp.flashInfo()
            #expect(flash.detectedSize != nil, "JEDEC ID \(String(flash.jedecID, radix: 16))")

            print("ESP32-S3: MAC \(mac), flash \(String(flash.jedecID, radix: 16)) \(flash.detectedSize.map(String.init(describing:)) ?? "?"), security \(security.flags.rawValue)")
            await esp.disconnect(.hard)
        }

        @Test("ESP32: flash a real firmware and boot", .enabled(if: esp32Port != nil && esp32Firmware != nil))
        func esp32Flash() async throws {
            try await flashAndBoot(port: esp32Port!, chip: .esp32, firmware: esp32Firmware!)
        }

        @Test("ESP32-S3: flash a real firmware and boot", .enabled(if: s3Port != nil && s3Firmware != nil))
        func s3Flash() async throws {
            try await flashAndBoot(port: s3Port!, chip: .esp32s3, firmware: s3Firmware!)
        }

        @Test("Ports present", .enabled(if: esp32Port != nil || s3Port != nil))
        func portsAreListed() throws {
            let ports = try SerialPorts.available()
            for path in [esp32Port, s3Port].compactMap({ $0 }) {
                #expect(ports.contains { $0.path == path }, "\(path) missing from \(ports.map(\.path))")
            }
        }
    }
}

// MARK: - Phase 1 milestone

/// Bootloader, partition table and application of a PlatformIO build.
func firmwareBuild(_ folder: String) throws -> FlashRegions {
    let url = URL(fileURLWithPath: folder)
    return FlashRegions(bootloader: try Data(contentsOf: url.appendingPathComponent("bootloader.bin")),
                        partitionTable: try Data(contentsOf: url.appendingPathComponent("partitions.bin")),
                        application: try Data(contentsOf: url.appendingPathComponent("firmware.bin")))
}

private func flashAndBoot(port: String, chip: ChipFamily, firmware: String) async throws {
    let build = try firmwareBuild(firmware)
    let regions = try build.resolved(for: chip)
    var options = ConnectOptions()                       // stub v2 and 460,800 baud by default
    options.expectedChip = chip
    let clock = ContinuousClock()
    let connectStart = clock.now
    let esp = try await ESPDevice.connect(port: port, options: options)
    let connected = clock.now - connectStart
    guard case .stub(let version) = await esp.state else {
        Issue.record("the stub is not running")
        return
    }
    #expect(await esp.baudRate == 460_800)

    let writeStart = clock.now
    let report = try await esp.writeFlash(build).value
    let written = clock.now - writeStart
    #expect(report.regions.map(\.address) == regions.map(\.address))

    let readStart = clock.now
    for region in regions {
        let back = try await esp.readFlash(at: region.address, count: region.data.count).value
        #expect(back == region.data, "read-back at 0x\(String(region.address, radix: 16))")
    }
    let read = clock.now - readStart
    await esp.disconnect(.hard)

    let total = regions.reduce(0) { $0 + $1.data.count }
    let sent = report.regions.reduce(0) { $0 + $1.bytesSent }
    print("\(chip): \(version), connection \(connected), wrote \(total) B (\(sent) B sent) in \(written), read back in \(read)")

    let marker = "ESPKit HIL OK \(chip.rawValue)"
    let output = try await captureConsole(port: port, until: marker, timeout: .seconds(10))
    #expect(output.contains(marker), "console: \(output.suffix(400).debugDescription)")
}

/// Reads the application console after the reset. Over USB-Serial-JTAG the port goes away
/// during the reset, so opening it is retried.
private func captureConsole(port path: String, until marker: String, timeout: Duration) async throws -> String {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var port: SerialPort?
    while port == nil {
        let candidate = SerialPort(path: path)
        do {
            try await candidate.open()
            port = candidate
        } catch {
            guard clock.now < deadline else { throw error }
            try await Task.sleep(for: .milliseconds(200))
        }
    }
    guard let port else { return "" }
    try await port.setBaudRate(115_200)
    try await port.setControlLines(dtr: false, rts: false)  // EN and GPIO0 released: the application runs
    var text = ""
    while clock.now < deadline, !text.contains(marker) {
        let data = (try? await port.read(maxCount: 1024, timeout: .milliseconds(200))) ?? Data()
        text += String(decoding: data, as: UTF8.self)
    }
    await port.close()
    return text
}
