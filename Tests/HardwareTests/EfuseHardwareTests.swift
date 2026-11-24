// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPKit

// Jalon de la phase 4 : lire les eFuses sur la carte et obtenir le même résumé qu'espefuse.
// ESPKIT_EFUSE_REFERENCES désigne un dossier avec `summary-<puce>.json` et `dump-<puce>.txt`
// relevés par espefuse sur les mêmes cartes (lecture seule).

private let environment = ProcessInfo.processInfo.environment
private let references = environment["ESPKIT_EFUSE_REFERENCES"].map { URL(fileURLWithPath: $0) }

@Suite("eFuses sur carte", .serialized)
struct EfuseHardwareTests {
    @Test("ESP32 : eFuses identiques à espefuse", .enabled(if: environment["ESPKIT_PORT_ESP32"] != nil && references != nil))
    func esp32() async throws { try await compare(port: environment["ESPKIT_PORT_ESP32"]!, chip: .esp32) }

    @Test("ESP32-S3 : eFuses identiques à espefuse", .enabled(if: environment["ESPKIT_PORT_S3"] != nil && references != nil))
    func s3() async throws { try await compare(port: environment["ESPKIT_PORT_S3"]!, chip: .esp32s3) }
}

private func compare(port: String, chip: ChipFamily) async throws {
    var options = ConnectOptions()
    options.expectedChip = chip
    let esp = try await ESPDevice.connect(port: port, options: options)
    let efuses = try await EfuseController(device: esp)
    await esp.disconnect(.hard)

    let summary = await efuses.summaryJSON()
    let expected = try Data(contentsOf: references!.appendingPathComponent("summary-\(chip.rawValue).json"))
    #expect(summary == expected, "résumé différent de celui d'espefuse")

    let dump = try String(contentsOf: references!.appendingPathComponent("dump-\(chip.rawValue).txt"), encoding: .utf8)
    let words = dump.split(separator: "\n").compactMap { line -> [UInt32]? in
        guard let range = line.range(of: "dump:") else { return nil }
        return line[range.upperBound...].split(separator: " ").compactMap { UInt32($0, radix: 16) }
    }
    #expect(await efuses.blocks().map(\.words) == words)
    #expect(await efuses.codingErrors().isEmpty)
    let mac = try #require(await efuses.field("MAC"))
    print("\(chip) : \(await efuses.fields().count) champs, MAC \(mac.displayValue), calibration \(await efuses.adcCalibration().map { "v\($0.blockVersion ?? 0), \($0.values.count) valeurs" } ?? "—")")
}
