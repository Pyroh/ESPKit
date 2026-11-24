// SPDX-License-Identifier: MIT OR Apache-2.0

/// Adopted by every ESPKit error.
///
/// `catch let error as any ESPKitError` catches all of them, whatever the domain.
/// Each module defines its own types (`TransportError`, `ProtocolError`…).
public protocol ESPKitError: Error, CustomStringConvertible, Sendable {}
