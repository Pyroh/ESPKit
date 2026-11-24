// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Minimal JSON value, serialized exactly like Python's `json.dumps(…, indent=4, sort_keys=True)`,
/// so that `summaryJSON()` can be compared with espefuse's output.
enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    /// Keys already in the wanted order.
    indirect case object([(String, JSONValue)])

    /// Text of the value when shown on its own (`EfuseField.displayValue`).
    var text: String {
        switch self {
        case .null: "null"
        case .bool(let flag): flag ? "True" : "False"
        case .int(let number): String(number)
        case .double(let number): number.description
        case .string(let text): text
        case .object: ""
        }
    }

    func pythonJSON(indent: Int = 0) -> String {
        switch self {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let number): return String(number)
        case .double(let number): return number.description
        case .string(let text): return Self.quoted(text)
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let inner = String(repeating: " ", count: indent + 4)
            let body = members.map { inner + Self.quoted($0.0) + ": " + $0.1.pythonJSON(indent: indent + 4) }
            return "{\n" + body.joined(separator: ",\n") + "\n" + String(repeating: " ", count: indent) + "}"
        }
    }

    /// Python's escaping (`ensure_ascii=True`).
    private static func quoted(_ text: String) -> String {
        var out = "\""
        for unit in text.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x20..<0x7F: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            default: out += String(format: "\\u%04x", unit)
            }
        }
        return out + "\""
    }
}
