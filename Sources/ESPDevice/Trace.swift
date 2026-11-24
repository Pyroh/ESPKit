// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTransport

/// Low-level events, the equivalent of `esptool --trace`.
public enum TraceEvent: Sendable, CustomStringConvertible {
    /// Which way bytes travelled.
    public enum Direction: Sendable {
        /// From the host to the chip.
        case sent
        /// From the chip to the host.
        case received
    }

    /// A DTR/RTS action of a reset sequence.
    case resetStep(ResetSequence.Step)
    /// A command sent to the chip.
    case sent(opcode: UInt8, payload: Data)
    /// A response from the chip: its value word, payload and status byte (0 = success).
    case received(opcode: UInt8, value: UInt32, payload: Data, status: UInt8)
    /// Bytes outside the protocol: ROM boot log, application output…
    case rawBytes(direction: Direction, Data)
    /// Both sides switched to this baud rate.
    case baudRateChanged(Int)
    /// The stub answered `OHAI`.
    case stubStarted(StubImage.Version)

    /// One line, close to `esptool --trace`.
    public var description: String {
        switch self {
        case .resetStep(let step): "reset   \(step)"
        case .sent(let opcode, let payload): "→ \(hex(opcode)) \(payload.count) B \(payload.hexPreview)"
        case .received(let opcode, let value, let payload, let status):
            "← \(hex(opcode)) val=\(hex(value)) status=\(status) \(payload.count) B \(payload.hexPreview)"
        case .rawBytes(let direction, let data):
            "\(direction == .sent ? "→" : "←") raw \(data.count) B \(String(decoding: data, as: UTF8.self).debugDescription)"
        case .baudRateChanged(let rate): "baud    \(rate)"
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
