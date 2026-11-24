// SPDX-License-Identifier: MIT OR Apache-2.0

/// Comment faire entrer la puce en mode téléchargement.
///
/// Sur les cartes de développement, DTR pilote GPIO0 (broche de boot) et RTS pilote EN (reset),
/// à travers deux transistors : une ligne active tire la broche à l'état bas.
public enum EntryReset: Hashable, Sendable {
    /// USB-Serial-JTAG si le port l'annonce ; sinon alternance UnixTight / classique.
    case automatic
    case classic(holdBootFor: Duration = .milliseconds(50))
    case unixTight(holdBootFor: Duration = .milliseconds(50))
    case usbSerialJTAG
    case custom(ResetSequence)
    /// Ne touche pas aux lignes : la puce est déjà en mode téléchargement.
    case none
}

/// Que faire de la puce en fin de session.
public enum ExitReset: Hashable, Sendable {
    /// Redémarre sur l'application.
    case hard
    /// Reset logiciel via le stub.
    case soft
    /// Reset par watchdog RTC (puces USB-OTG).
    case watchdog
    /// Ne fait rien.
    case stayInBootloader
    /// Laisse le stub actif pour une reconnexion.
    case stayInStub
}

/// Suite d'actions sur DTR/RTS (équivalent de `--before custom`).
public struct ResetSequence: Hashable, Sendable, ExpressibleByArrayLiteral {
    public enum Step: Hashable, Sendable {
        case dtr(Bool), rts(Bool)
        /// Les deux lignes en un seul appel système.
        case lines(dtr: Bool, rts: Bool)
        case wait(Duration)
    }

    public var steps: [Step]

    public init(_ steps: [Step]) { self.steps = steps }
    public init(arrayLiteral elements: Step...) { self.steps = elements }
}

extension ResetSequence {
    /// Reset séquentiel portable : EN bas, puis relâché avec GPIO0 maintenu bas.
    public static func classic(holdBootFor hold: Duration = .milliseconds(50)) -> ResetSequence {
        [
            .dtr(false), .rts(true),          // GPIO0 haut, EN bas : puce en reset
            .wait(.milliseconds(100)),
            .dtr(true), .rts(false),          // GPIO0 bas, EN haut : la puce démarre en mode téléchargement
            .wait(hold),
            .dtr(false),                      // GPIO0 relâché
        ]
    }

    /// Variante POSIX : les deux lignes changent ensemble, sans état intermédiaire parasite.
    public static func unixTight(holdBootFor hold: Duration = .milliseconds(50)) -> ResetSequence {
        [
            .lines(dtr: false, rts: false),
            .lines(dtr: true, rts: true),
            .lines(dtr: false, rts: true),    // GPIO0 haut, EN bas
            .wait(.milliseconds(100)),
            .lines(dtr: true, rts: false),    // GPIO0 bas, EN haut
            .wait(hold),
            .lines(dtr: false, rts: false),
            .dtr(false),
        ]
    }

    /// Périphérique USB-Serial-JTAG intégré : DTR et RTS sont virtuels, la séquence passe
    /// par (1,1) plutôt que (0,0).
    public static let usbSerialJTAG: ResetSequence = [
        .rts(false), .dtr(false),
        .wait(.milliseconds(100)),
        .dtr(true), .rts(false),
        .wait(.milliseconds(100)),
        .rts(true), .dtr(false), .rts(true),
        .wait(.milliseconds(100)),
        .dtr(false), .rts(false),
    ]

    /// Impulsion sur EN pour redémarrer la puce. Sur un lien USB natif, la puce disparaît
    /// du bus pendant le reset : on lui laisse le temps de revenir.
    public static func hardReset(overUSB: Bool) -> ResetSequence {
        overUSB
            ? [.rts(true), .wait(.milliseconds(200)), .rts(false), .wait(.milliseconds(200))]
            : [.rts(true), .wait(.milliseconds(100)), .rts(false)]
    }
}

extension Transport {
    /// Joue une séquence de reset sur ce transport.
    public func perform(_ sequence: ResetSequence) async throws {
        for step in sequence.steps {
            try await perform(step)
        }
    }

    /// Joue une seule étape.
    public func perform(_ step: ResetSequence.Step) async throws {
        switch step {
        case .dtr(let value): try await setControlLines(dtr: value, rts: nil)
        case .rts(let value): try await setControlLines(dtr: nil, rts: value)
        case .lines(let dtr, let rts): try await setControlLines(dtr: dtr, rts: rts)
        case .wait(let duration): try await Task.sleep(for: duration)
        }
    }
}
