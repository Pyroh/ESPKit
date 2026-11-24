// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Programme chargé en RAM pour accélérer et étendre le protocole de la ROM.
public struct StubImage: Sendable, Hashable {
    /// Puce visée. Charger un stub sur une autre puce lève `StubError.chipMismatch`.
    public var chip: ChipFamily
    public var text: Data
    public var textAddress: UInt32
    public var data: Data
    public var dataAddress: UInt32
    public var entry: UInt32
    /// Début de la zone BSS, quand le format la donne. Informatif : ESPKit ne s'en sert que
    /// pour vérifier que les segments ne la recouvrent pas.
    public var bssStart: UInt32?
    public var version: Version

    public enum Version: Sendable, Hashable, CustomStringConvertible {
        /// Stub v2 embarqué ; la chaîne est la version d'`esp-flasher-stub` embarquée.
        case bundled(String)
        /// Stub fourni par l'appelant, avec une étiquette libre pour la trace et les rapports.
        case custom(String?)

        public var description: String {
            switch self {
            case .bundled(let version): "esp-flasher-stub \(version)"
            case .custom(let label): label ?? "personnalisé"
            }
        }
    }

    /// Image brute : l'appelant fournit lui-même segments, adresses et point d'entrée.
    /// - Throws: `StubError.malformed` si le segment de code est vide ou si une adresse
    ///   n'est pas alignée sur 4 octets ; `StubError.overlapping` si les segments se recouvrent.
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
        guard !text.isEmpty else { throw StubError.malformed("segment de code vide") }
        for (name, address) in [("text_start", textAddress), ("data_start", dataAddress)] where address % 4 != 0 {
            throw StubError.malformed("\(name) \(hex(address)) n'est pas aligné sur 4 octets")
        }
        let textRange = UInt64(textAddress)..<UInt64(textAddress) + UInt64(text.count)
        let dataRange = UInt64(dataAddress)..<UInt64(dataAddress) + UInt64(data.count)
        if !data.isEmpty && textRange.overlaps(dataRange) {
            throw StubError.overlapping("les segments text et data se recouvrent")
        }
        if let bssStart {
            let bss = UInt64(bssStart)
            if textRange.contains(bss) || (!data.isEmpty && dataRange.contains(bss) && bss != dataRange.lowerBound) {
                throw StubError.overlapping("bss_start \(hex(bssStart)) tombe dans un segment")
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

    /// Lit le format JSON des stubs publiés par `esp-flasher-stub` (et par esptool) :
    /// `entry`, `text`, `text_start`, `data`, `data_start`, `bss_start`, segments en base64.
    /// Le fichier ne nomme pas la puce : l'appelant la donne.
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
            throw StubError.malformed("JSON illisible (\(error))")
        }
        guard let text = Data(base64Encoded: payload.text) else {
            throw StubError.malformed("champ text : base64 invalide")
        }
        var data = Data()
        if let encoded = payload.data {
            guard let decoded = Data(base64Encoded: encoded) else {
                throw StubError.malformed("champ data : base64 invalide")
            }
            data = decoded
        }
        try self.init(chip: chip, text: text, textAddress: payload.text_start,
                      data: data, dataAddress: payload.data_start ?? 0,
                      entry: payload.entry, bssStart: payload.bss_start, version: version)
    }

    /// Stub v2 embarqué pour cette puce. `nil` pour l'ESP32-E22, que le stub v2 ne couvre pas.
    ///
    /// Phase 0 : aucun stub n'est encore embarqué ; la fonction rend toujours `nil`.
    public static func bundled(for chip: ChipFamily) -> StubImage? {
        nil
    }
}
