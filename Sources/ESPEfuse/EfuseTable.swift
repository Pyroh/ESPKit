// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets

/// Intervalle de bits dans un bloc.
struct Bits: Hashable, Sendable {
    let start: Int
    let count: Int
    init(_ start: Int, _ count: Int) {
        self.start = start
        self.count = count
    }
}

/// Champ décrit par la table d'ESP-IDF (fichier généré).
struct EfuseDefinition: Sendable {
    let name: String
    let idfName: String
    let aliases: [String]
    let block: Int
    let bits: [Bits]
    let description: String
    let category: String
    let type: String
    let inSummary: Bool
    let writeDisableBit: Int?
    let readDisableBit: Int?
    let values: [UInt64: String]

    var bitCount: Int { bits.reduce(0) { $0 + $1.count } }

    func matches(_ name: String) -> Bool {
        name == self.name || name == idfName || aliases.contains(name)
    }
}

/// Champ qu'espefuse calcule à partir d'autres (libellés seulement ; le calcul est dans ESPKit).
struct CompositeLabel: Sendable {
    let name: String
    let block: Int
    let bitCount: Int
    let description: String
    let category: String
    let type: String
}

struct EfuseTable: Sendable {
    let chip: ChipFamily
    let fields: [EfuseDefinition]
    let composites: [CompositeLabel]

    static func table(for chip: ChipFamily) -> EfuseTable? {
        switch chip {
        case .esp32: .esp32
        case .esp32s2: .esp32s2
        case .esp32s3: .esp32s3
        case .esp32c2: .esp32c2
        case .esp32c3: .esp32c3
        case .esp32c5: .esp32c5
        case .esp32c6: .esp32c6
        case .esp32c61: .esp32c61
        case .esp32h2: .esp32h2
        case .esp32h21: .esp32h21
        case .esp32h4: .esp32h4
        case .esp32p4: .esp32p4
        case .esp8266, .esp32s31, .esp32e22: nil
        }
    }

    func definition(named name: String) -> EfuseDefinition? {
        fields.first { $0.matches(name) }
    }
}

/// Registres de lecture du contrôleur d'eFuses (en-têtes `efuse_reg.h` d'ESP-IDF).
struct EfuseLayout: Sendable {
    struct Block: Sendable {
        let name: String
        let address: UInt32
        let wordCount: Int
    }

    let blocks: [Block]
    let errorRegisters: [UInt32]
    let apbControlDate: UInt32?

    static func layout(for chip: ChipFamily) -> EfuseLayout? {
        switch chip {
        case .esp32:
            let base: UInt32 = 0x3FF5_A000
            return EfuseLayout(blocks: [Block(name: "BLOCK0", address: base, wordCount: 7),
                                        Block(name: "BLOCK1", address: base + 0x38, wordCount: 8),
                                        Block(name: "BLOCK2", address: base + 0x58, wordCount: 8),
                                        Block(name: "BLOCK3", address: base + 0x78, wordCount: 8)],
                               errorRegisters: [base + 0x11C],          // EFUSE_DEC_STATUS
                               apbControlDate: 0x3FF6_607C)             // APB_CTRL_DATE
        case .esp32s3:
            let base: UInt32 = 0x6000_7000
            var blocks = [Block(name: "BLOCK0", address: base + 0x2C, wordCount: 6),
                          Block(name: "MAC_SPI_8M_0", address: base + 0x44, wordCount: 6),
                          Block(name: "BLOCK_SYS_DATA", address: base + 0x5C, wordCount: 8),
                          Block(name: "BLOCK_USR_DATA", address: base + 0x7C, wordCount: 8)]
            for key in 0..<6 {
                blocks.append(Block(name: "BLOCK_KEY\(key)", address: base + 0x9C + UInt32(key) * 0x20, wordCount: 8))
            }
            blocks.append(Block(name: "BLOCK_SYS_DATA2", address: base + 0x15C, wordCount: 8))
            // RD_REPEAT_ERR0..4, puis RD_RS_ERR0 et RD_RS_ERR1.
            return EfuseLayout(blocks: blocks,
                               errorRegisters: (0..<5).map { base + 0x17C + UInt32($0) * 4 } + [base + 0x1C0, base + 0x1C4],
                               apbControlDate: nil)
        default:
            return nil
        }
    }

    /// Nombre de mots par bloc, pour un contrôleur virtuel vierge.
    static func blankBlocks(for chip: ChipFamily) -> [[UInt32]] {
        if let layout = layout(for: chip) { return layout.blocks.map { Array(repeating: 0, count: $0.wordCount) } }
        // Puces sans registres connus : BLOCK0 de 6 mots, puis blocs de 8 mots.
        let count = (EfuseTable.table(for: chip)?.fields.map(\.block).max() ?? 10) + 1
        return [Array(repeating: 0, count: 6)] + Array(repeating: Array(repeating: 0, count: 8), count: max(count - 1, 0))
    }
}
