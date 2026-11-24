// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPKit

// Tests sur carte réelle. Ignorés tant que les variables d'environnement ne sont pas définies :
//
//   ESPKIT_PORT_ESP32=/dev/cu.usbserial-0001 ESPKIT_PORT_S3=/dev/cu.usbmodem1101 swift test --filter HardwareTests
//
// Jalon de la phase 0 : détection, MAC et identité de la flash sur l'ESP32 et l'ESP32-S3, en ROM.

private let esp32Port = ProcessInfo.processInfo.environment["ESPKIT_PORT_ESP32"]
private let s3Port = ProcessInfo.processInfo.environment["ESPKIT_PORT_S3"]

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

    @Test("Ports présents", .enabled(if: esp32Port != nil || s3Port != nil))
    func portsAreListed() throws {
        let ports = try SerialPorts.available()
        for path in [esp32Port, s3Port].compactMap({ $0 }) {
            #expect(ports.contains { $0.path == path }, "\(path) absent de \(ports.map(\.path))")
        }
    }
}
