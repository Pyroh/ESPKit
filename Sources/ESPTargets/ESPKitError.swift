// SPDX-License-Identifier: MIT OR Apache-2.0

/// Conformé par toutes les erreurs propres à ESPKit.
///
/// `catch let error as any ESPKitError` les attrape toutes, quel que soit le domaine.
/// Chaque module définit ses propres types (`TransportError`, `ProtocolError`…).
public protocol ESPKitError: Error, CustomStringConvertible, Sendable {}
