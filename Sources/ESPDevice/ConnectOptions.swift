// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets
import ESPTransport

/// Réglages de `ESPDevice.connect`.
public struct ConnectOptions: Sendable {
    public var entryReset: EntryReset = .automatic
    /// Débit de synchro, plafonné à 115 200 comme le fait esptool.
    public var initialBaudRate: Int = 115_200
    /// Débit de travail, appliqué après le chargement du stub. `nil` = rester au débit initial.
    public var baudRate: Int? = 460_800
    public var stub: StubPolicy = .load
    /// `nil` : détection automatique. Sinon, erreur si la puce détectée diffère.
    public var expectedChip: ChipFamily? = nil
    /// 0 = infini.
    public var connectAttempts: Int = 7
    /// Saute la synchro (`--before no-reset-no-sync`) : la puce parle déjà le protocole.
    public var skipSync: Bool = false
    /// ESP32 seulement : forcer le régulateur VDDSDIO.
    public var vddsdioOverride: VDDSDIOOverride? = nil
    /// Reçoit la trace bas niveau dès le premier reset. `nil` = pas de trace.
    public var trace: AsyncStream<TraceEvent>.Continuation? = nil

    public init() {}
}

public enum StubPolicy: Sendable, Hashable {
    /// Stub v2 embarqué pour la puce détectée (défaut).
    case load
    /// `--no-stub`.
    case romOnly
    /// Stub fourni par l'appelant.
    case custom(StubImage)
}

/// Tension forcée du régulateur VDDSDIO de l'ESP32 (alimentation de la flash).
public enum VDDSDIOOverride: Hashable, Sendable {
    case volts1_8, volts1_9, off
}
