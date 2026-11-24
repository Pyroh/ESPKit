// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Program loaded into RAM to speed up and extend the ROM protocol.
public struct StubImage: Sendable, Hashable {
    /// Target chip. Loading a stub onto another chip throws `StubError.chipMismatch`.
    public var chip: ChipFamily
    /// Code segment.
    public var text: Data
    /// RAM address where ``text`` is loaded.
    public var textAddress: UInt32
    /// Data segment (may be empty).
    public var data: Data
    /// RAM address where ``data`` is loaded.
    public var dataAddress: UInt32
    /// Entry point the ROM jumps to.
    public var entry: UInt32
    /// Start of the BSS area, when the format provides it. Informational: ESPKit only uses it
    /// to check that the segments do not overlap it.
    public var bssStart: UInt32?
    /// Where the stub comes from, for the trace and `ESPDevice.State`.
    public var version: Version

    /// Origin of a stub.
    public enum Version: Sendable, Hashable, CustomStringConvertible {
        /// Bundled stub v2; the string is the bundled `esp-flasher-stub` version.
        case bundled(String)
        /// Stub supplied by the caller, with a free label for the trace and reports.
        case custom(String?)

        /// For example "esp-flasher-stub 2.0.0".
        public var description: String {
            switch self {
            case .bundled(let version): "esp-flasher-stub \(version)"
            case .custom(let label): label ?? "custom"
            }
        }
    }

    /// Raw image: the caller provides the segments, addresses and entry point.
    /// - Throws: `StubError.malformed` if the code segment is empty or an address
    ///   is not 4-byte aligned; `StubError.overlapping` if the segments overlap.
    public init(chip: ChipFamily,
                text: Data, textAddress: UInt32,
                data: Data, dataAddress: UInt32,
                entry: UInt32, bssStart: UInt32? = nil,
                label: String? = nil) throws {
        try self.init(chip: chip, text: text, textAddress: textAddress, data: data, dataAddress: dataAddress,
                      entry: entry, bssStart: bssStart, version: .custom(label))
    }

    init(chip: ChipFamily, text: Data, textAddress: UInt32, data: Data, dataAddress: UInt32,
         entry: UInt32, bssStart: UInt32?, version: Version) throws {
        guard !text.isEmpty else { throw StubError.malformed("empty code segment") }
        for (name, address) in [("text_start", textAddress), ("data_start", dataAddress)] where address % 4 != 0 {
            throw StubError.malformed("\(name) \(hex(address)) is not 4-byte aligned")
        }
        let textRange = UInt64(textAddress)..<UInt64(textAddress) + UInt64(text.count)
        let dataRange = UInt64(dataAddress)..<UInt64(dataAddress) + UInt64(data.count)
        if !data.isEmpty && textRange.overlaps(dataRange) {
            throw StubError.overlapping("the text and data segments overlap")
        }
        if let bssStart {
            let bss = UInt64(bssStart)
            if textRange.contains(bss) || (!data.isEmpty && dataRange.contains(bss) && bss != dataRange.lowerBound) {
                throw StubError.overlapping("bss_start \(hex(bssStart)) falls inside a segment")
            }
        }
        self.chip = chip
        self.text = text
        self.textAddress = textAddress
        self.data = data
        self.dataAddress = dataAddress
        self.entry = entry
        self.bssStart = bssStart
        self.version = version
    }

    /// Reads the JSON format of the stubs published by `esp-flasher-stub` (and esptool):
    /// `entry`, `text`, `text_start`, `data`, `data_start`, `bss_start`, base64 segments.
    /// The file does not name the chip: the caller provides it.
    /// - Throws: `StubError.malformed`, `StubError.overlapping`.
    public init(json: Data, chip: ChipFamily, label: String? = nil) throws {
        try self.init(json: json, chip: chip, version: .custom(label))
    }

    init(json: Data, chip: ChipFamily, version: Version) throws {
        struct Payload: Decodable {
            var entry: UInt32
            var text: String
            var text_start: UInt32
            var data: String?
            var data_start: UInt32?
            var bss_start: UInt32?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: json)
        } catch {
            throw StubError.malformed("unreadable JSON (\(error))")
        }
        guard let text = Data(base64Encoded: payload.text) else {
            throw StubError.malformed("text field: invalid base64")
        }
        var data = Data()
        if let encoded = payload.data {
            guard let decoded = Data(base64Encoded: encoded) else {
                throw StubError.malformed("data field: invalid base64")
            }
            data = decoded
        }
        try self.init(chip: chip, text: text, textAddress: payload.text_start,
                      data: data, dataAddress: payload.data_start ?? 0,
                      entry: payload.entry, bssStart: payload.bss_start, version: version)
    }

    /// Bundled stub v2 for this chip. `nil` for the ESP32-E22, which stub v2 does not cover.
    ///
    /// The images come from `esp-flasher-stub` (Espressif, MIT OR Apache-2.0). For the ESP32-P4,
    /// it is the image for revision 3 and later.
    public static func bundled(for chip: ChipFamily) -> StubImage? {
        guard let json = bundledJSON(for: chip) else { return nil }
        // The bundled images are validated by the tests: a failure here would be an ESPKit bug.
        return try? StubImage(json: Data(json.utf8), chip: chip, version: .bundled(bundledVersion))
    }
}
