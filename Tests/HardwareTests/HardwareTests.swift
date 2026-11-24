// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPKit

// Tests sur carte réelle. Ignorés tant que les variables d'environnement ne sont pas définies :
//
//   ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
//
// Jalon de la phase 0 : détection, MAC et identité de la flash sur l'ESP32 et l'ESP32-S3, en ROM.
//
// Jalon de la phase 1 : flasher un vrai build PlatformIO (bootloader, partitions, application) avec
// le stub, relire, puis constater le démarrage. Le dossier du build se donne par variable :
//
//   ESPKIT_FIRMWARE_ESP32=…/.pio/build/esp32 ESPKIT_FIRMWARE_S3=…/.pio/build/esp32s3
//
// L'application doit écrire « ESPKit HIL OK <puce> » sur sa console (voir README).

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

@Suite("Matériel", .serialized)
struct HardwareTests {
    @Test("ESP32 : détection, MAC, flash", .enabled(if: esp32Port != nil))
    func esp32Identity() async throws {
        let esp = try await ESPDevice.connect(port: try #require(esp32Port), options: romOnly(expecting: .esp32))
        #expect(esp.chip == .esp32)
        #expect(await esp.state == .rom)

        let mac = try await esp.macAddress()
        #expect(mac.bytes != Data(count: 6))

        let flash = try await esp.flashInfo()
        #expect(flash.detectedSize != nil, "ID JEDEC \(String(flash.jedecID, radix: 16))")

        await #expect(throws: UsageError.self) { try await esp.chipID() }
        print("ESP32 : MAC \(mac), flash \(String(flash.jedecID, radix: 16)) \(flash.detectedSize.map(String.init(describing:)) ?? "?")")
        await esp.disconnect(.hard)
    }

    @Test("ESP32-S3 : détection, sécurité, MAC, flash", .enabled(if: s3Port != nil))
    func s3Identity() async throws {
        let esp = try await ESPDevice.connect(port: try #require(s3Port), options: romOnly(expecting: .esp32s3))
        #expect(esp.chip == .esp32s3)

        let security = try await esp.securityInfo()
        #expect(security.chipID == 9)

        let mac = try await esp.macAddress()
        #expect(mac.bytes != Data(count: 6))

        let flash = try await esp.flashInfo()
        #expect(flash.detectedSize != nil, "ID JEDEC \(String(flash.jedecID, radix: 16))")

        print("ESP32-S3 : MAC \(mac), flash \(String(flash.jedecID, radix: 16)) \(flash.detectedSize.map(String.init(describing:)) ?? "?"), sécurité \(security.flags.rawValue)")
        await esp.disconnect(.hard)
    }

    @Test("ESP32 : flash d'un vrai firmware et démarrage", .enabled(if: esp32Port != nil && esp32Firmware != nil))
    func esp32Flash() async throws {
        try await flashAndBoot(port: esp32Port!, chip: .esp32, firmware: esp32Firmware!)
    }

    @Test("ESP32-S3 : flash d'un vrai firmware et démarrage", .enabled(if: s3Port != nil && s3Firmware != nil))
    func s3Flash() async throws {
        try await flashAndBoot(port: s3Port!, chip: .esp32s3, firmware: s3Firmware!)
    }

    @Test("Ports présents", .enabled(if: esp32Port != nil || s3Port != nil))
    func portsAreListed() throws {
        let ports = try SerialPorts.available()
        for path in [esp32Port, s3Port].compactMap({ $0 }) {
            #expect(ports.contains { $0.path == path }, "\(path) absent de \(ports.map(\.path))")
        }
    }
}

// MARK: - Jalon de la phase 1

/// Bootloader, table de partitions et application d'un build PlatformIO.
private func firmwareRegions(_ folder: String, chip: ChipFamily) throws -> [FlashRegion] {
    let url = URL(fileURLWithPath: folder)
    return [
        FlashRegion(address: chip.bootloaderOffset, data: try Data(contentsOf: url.appendingPathComponent("bootloader.bin"))),
        FlashRegion(address: 0x8000, data: try Data(contentsOf: url.appendingPathComponent("partitions.bin"))),
        FlashRegion(address: 0x1_0000, data: try Data(contentsOf: url.appendingPathComponent("firmware.bin"))),
    ]
}

private func flashAndBoot(port: String, chip: ChipFamily, firmware: String) async throws {
    let regions = try firmwareRegions(firmware, chip: chip)
    var options = ConnectOptions()                       // stub v2 et 460 800 bauds par défaut
    options.expectedChip = chip
    let clock = ContinuousClock()
    let connectStart = clock.now
    let esp = try await ESPDevice.connect(port: port, options: options)
    let connected = clock.now - connectStart
    guard case .stub(let version) = await esp.state else {
        Issue.record("le stub ne tourne pas")
        return
    }
    #expect(await esp.baudRate == 460_800)

    let writeStart = clock.now
    let report = try await esp.writeFlash(regions).value
    let written = clock.now - writeStart
    #expect(report.regions.count == 3)

    let readStart = clock.now
    for region in regions {
        let back = try await esp.readFlash(at: region.address, count: region.data.count).value
        #expect(back == region.data, "relecture à 0x\(String(region.address, radix: 16))")
    }
    let read = clock.now - readStart
    await esp.disconnect(.hard)

    let total = regions.reduce(0) { $0 + $1.data.count }
    let sent = report.regions.reduce(0) { $0 + $1.bytesSent }
    print("\(chip) : \(version), connexion \(connected), écriture de \(total) o (\(sent) o envoyés) en \(written), relecture en \(read)")

    let marker = "ESPKit HIL OK \(chip.rawValue)"
    let output = try await captureConsole(port: port, until: marker, timeout: .seconds(10))
    #expect(output.contains(marker), "console : \(output.suffix(400).debugDescription)")
}

/// Lit la console de l'application après le reset. Sur l'USB-Serial-JTAG, le port disparaît
/// pendant le reset : on réessaie de l'ouvrir.
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
    try await port.setControlLines(dtr: false, rts: false)  // EN et GPIO0 relâchés : l'application tourne
    var text = ""
    while clock.now < deadline, !text.contains(marker) {
        let data = (try? await port.read(maxCount: 1024, timeout: .milliseconds(200))) ?? Data()
        text += String(decoding: data, as: UTF8.self)
    }
    await port.close()
    return text
}
