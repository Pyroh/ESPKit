// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPEfuse

// Comparison with espefuse, used as a black box. Skipped unless ESPKIT_EFUSE_REFERENCES
// names a folder holding, for a chip, `dump-<chip>.txt` (espefuse dump) and
// `summary-<chip>.json` (espefuse summary --format json) taken from the same board.
// The virtual controller is filled with the dump's blocks, then its summary is compared.

private let folder = ProcessInfo.processInfo.environment["ESPKIT_EFUSE_REFERENCES"].map { URL(fileURLWithPath: $0) }

/// Blocks of an `espefuse dump`: "NAME (…) [n] dump: word word …".
func blocks(fromDump text: String) -> [[UInt32]] {
    var blocks: [Int: [UInt32]] = [:]
    for line in text.split(separator: "\n") {
        guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]"),
              let index = Int(line[line.index(after: open)..<close].trimmingCharacters(in: .whitespaces)),
              let dump = line.range(of: "dump:") else { continue }
        blocks[index] = line[dump.upperBound...].split(separator: " ").compactMap { UInt32($0, radix: 16) }
    }
    return blocks.sorted { $0.key < $1.key }.map(\.value)
}

/// Field-by-field differences, for a readable message.
func differences(_ ours: Data, _ theirs: Data) -> [String] {
    guard let a = try? JSONSerialization.jsonObject(with: ours) as? [String: [String: Any]],
          let b = try? JSONSerialization.jsonObject(with: theirs) as? [String: [String: Any]] else { return ["unreadable JSON"] }
    var out: [String] = []
    for name in Set(a.keys).union(b.keys).sorted() {
        guard let x = a[name] else { out.append("\(name): missing from ESPKit"); continue }
        guard let y = b[name] else { out.append("\(name): missing from espefuse"); continue }
        for key in Set(x.keys).union(y.keys).sorted() where "\(x[key] ?? "nil")" != "\(y[key] ?? "nil")" {
            out.append("\(name).\(key): ESPKit \(x[key] ?? "nil") / espefuse \(y[key] ?? "nil")")
        }
    }
    return out
}

@Suite("espefuse differential", .enabled(if: folder != nil))
struct EfuseReferenceTests {
    @Test(arguments: [ChipFamily.esp32, .esp32s3])
    func summaryMatchesEspefuse(chip: ChipFamily) async throws {
        let dump = try #require(folder).appendingPathComponent("dump-\(chip.rawValue).txt")
        guard FileManager.default.fileExists(atPath: dump.path) else { return }
        let snapshot = EfuseSnapshot(chip: chip, blocks: blocks(fromDump: try String(contentsOf: dump, encoding: .utf8)),
                                     errorRegisters: [], apbControlDate: chip == .esp32 ? 0x8000_0000 : nil)
        let controller = EfuseController(virtual: chip, initialState: snapshot)
        let ours = await controller.summaryJSON()
        let theirs = try Data(contentsOf: try #require(folder).appendingPathComponent("summary-\(chip.rawValue).json"))
        let issues = differences(ours, theirs)
        #expect(issues.isEmpty, "\(issues.count) difference(s):\n\(issues.prefix(30).joined(separator: "\n"))")
        #expect(ours == theirs, "JSON differs byte for byte")
    }
}
