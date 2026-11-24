// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPEfuse

// Comparaison avec espefuse, utilisé comme boîte noire. Ignorés sauf si ESPKIT_EFUSE_REFERENCES
// désigne un dossier contenant, pour une puce, `dump-<puce>.txt` (espefuse dump) et
// `summary-<puce>.json` (espefuse summary --format json) relevés sur la même carte.
// Le contrôleur virtuel est rempli avec les blocs du dump, puis son résumé est comparé.

private let folder = ProcessInfo.processInfo.environment["ESPKIT_EFUSE_REFERENCES"].map { URL(fileURLWithPath: $0) }

/// Blocs d'un `espefuse dump` : « NOM (…) [n] dump: mot mot … ».
func blocks(fromDump text: String) -> [[UInt32]] {
    var blocks: [Int: [UInt32]] = [:]
    for line in text.split(separator: "\n") {
        guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"),
              let index = Int(line[line.index(after: open)..<close].trimmingCharacters(in: .whitespaces)),
              let dump = line.range(of: "dump:") else { continue }
        blocks[index] = line[dump.upperBound...].split(separator: " ").compactMap { UInt32($0, radix: 16) }
    }
    return blocks.keys.sorted().map { blocks[$0]! }
}

/// Différences champ par champ, pour un message lisible.
func differences(_ ours: Data, _ theirs: Data) -> [String] {
    guard let a = try? JSONSerialization.jsonObject(with: ours) as? [String: [String: Any]],
          let b = try? JSONSerialization.jsonObject(with: theirs) as? [String: [String: Any]] else { return ["JSON illisible"] }
    var out: [String] = []
    for name in Set(a.keys).union(b.keys).sorted() {
        guard let x = a[name] else { out.append("\(name) : absent chez ESPKit"); continue }
        guard let y = b[name] else { out.append("\(name) : absent chez espefuse"); continue }
        for key in Set(x.keys).union(y.keys).sorted() where "\(x[key] ?? "nil")" != "\(y[key] ?? "nil")" {
            out.append("\(name).\(key) : ESPKit \(x[key] ?? "nil") / espefuse \(y[key] ?? "nil")")
        }
    }
    return out
}

@Suite("Différentiel espefuse", .enabled(if: folder != nil))
struct EfuseReferenceTests {
    @Test(arguments: [ChipFamily.esp32, .esp32s3])
    func summaryMatchesEspefuse(chip: ChipFamily) async throws {
        let dump = folder!.appendingPathComponent("dump-\(chip.rawValue).txt")
        guard FileManager.default.fileExists(atPath: dump.path) else { return }
        let snapshot = EfuseSnapshot(chip: chip, blocks: blocks(fromDump: try String(contentsOf: dump, encoding: .utf8)),
                                     errorRegisters: [], apbControlDate: chip == .esp32 ? 0x8000_0000 : nil)
        let controller = EfuseController(virtual: chip, initialState: snapshot)
        let ours = await controller.summaryJSON()
        let theirs = try Data(contentsOf: folder!.appendingPathComponent("summary-\(chip.rawValue).json"))
        let issues = differences(ours, theirs)
        #expect(issues.isEmpty, "\(issues.count) écart(s) :\n\(issues.prefix(30).joined(separator: "\n"))")
        #expect(ours == theirs, "JSON différent à l'octet")
    }
}
