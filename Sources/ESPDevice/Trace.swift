// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTransport

/// Événements bas niveau, l'équivalent de `esptool --trace`.
public enum TraceEvent: Sendable, CustomStringConvertible {
    public enum Direction: Sendable { case sent, received }

    case resetStep(ResetSequence.Step)
    case sent(opcode: UInt8, payload: Data)
    case received(opcode: UInt8, value: UInt32, payload: Data, status: UInt8)
    /// Octets hors protocole : journal de boot de la ROM, sortie de l'application…
    case rawBytes(direction: Direction, Data)
    case baudRateChanged(Int)
    case stubStarted(StubImage.Version)

    public var description: String {
        switch self {
        case .resetStep(let step): "reset   \(step)"
        case .sent(let opcode, let payload): "→ \(hex(opcode)) \(payload.count) o \(payload.hexPreview)"
        case .received(let opcode, let value, let payload, let status):
            "← \(hex(opcode)) val=\(hex(value)) status=\(status) \(payload.count) o \(payload.hexPreview)"
        case .rawBytes(let direction, let data):
            "\(direction == .sent ? "→" : "←") brut \(data.count) o \(String(decoding: data, as: UTF8.self).debugDescription)"
        case .baudRateChanged(let rate): "débit   \(rate)"
        case .stubStarted(let version): "stub    \(version)"
        }
    }
}

extension Data {
    var hexPreview: String {
        let shown = prefix(32).map { String(format: "%02x", $0) }.joined()
        return count > 32 ? shown + "…" : shown
    }
}
