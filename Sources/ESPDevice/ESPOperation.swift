// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Opération longue sur la puce : écrire, lire, vérifier, effacer.
///
/// L'opération est **froide** : rien n'est envoyé à la puce avant qu'on la parcoure
/// ou qu'on attende `value`, et chaque parcours la relance.
/// Elle s'exécute dans l'isolation de l'`ESPDevice`, donc à la suite des autres opérations.
///
/// - Annuler la tâche qui parcourt, ou sortir de la boucle, arrête l'opération au bloc suivant ;
///   l'itération lève alors `CancellationError`.
/// - Les événements `.progress` ne bloquent jamais le transfert : si le consommateur est plus
///   lent que la puce, seule la progression la plus récente est conservée. `.finished` n'est
///   jamais perdu.
public struct ESPOperation<Success: Sendable>: AsyncSequence, Sendable {
    public typealias Element = ESPOperationEvent<Success>
    public typealias Failure = any Error

    private let body: @Sendable (ProgressSink) async throws -> Success

    init(_ body: @escaping @Sendable (ProgressSink) async throws -> Success) {
        self.body = body
    }

    /// Exécute l'opération jusqu'au bout sans suivre la progression.
    public var value: Success {
        get async throws { try await body(ProgressSink.discarding) }
    }

    /// Progression seule. Le résultat est jeté : à utiliser quand `Success == Void`
    /// ou quand on lit le résultat ailleurs.
    public var progress: some AsyncSequence<OperationProgress, any Error> & Sendable {
        ProgressOnly(operation: self)
    }

    public func makeAsyncIterator() -> Iterator {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: Element.self, throwing: (any Error).self, bufferingPolicy: .bufferingNewest(1))
        let body = self.body
        let task = Task {
            do {
                let value = try await body(ProgressSink(continuation))
                // Avec un tampon d'un élément, `.finished` remplace une progression non lue.
                continuation.yield(.finished(value))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return Iterator(base: stream.makeAsyncIterator())
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Element = ESPOperationEvent<Success>
        public typealias Failure = any Error

        var base: AsyncThrowingStream<Element, any Error>.Iterator
        var finished = false

        public mutating func next() async throws -> Element? {
            try await next(isolation: nil)
        }

        /// Les événements arrivent dans l'isolation de l'appelant (le main actor pour une UI).
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(any Error) -> Element? {
            guard !finished else { return nil }
            let event = try await base.next(isolation: actor)
            switch event {
            case .finished:
                finished = true
            case .progress:
                break
            case nil:
                // Flux terminé sans résultat : l'appelant a été annulé.
                finished = true
                throw CancellationError()
            }
            return event
        }
    }
}

public enum ESPOperationEvent<Success: Sendable>: Sendable {
    case progress(OperationProgress)
    /// Toujours le dernier événement d'un parcours qui réussit.
    case finished(Success)
}

public struct OperationProgress: Hashable, Sendable {
    public enum Stage: Hashable, Sendable { case preparing, erasing, writing, verifying, reading }

    public var stage: Stage
    public var regionIndex: Int
    public var regionCount: Int
    public var completedBytes: Int
    public var totalBytes: Int

    public var fractionCompleted: Double {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
    }

    public init(stage: Stage, regionIndex: Int, regionCount: Int, completedBytes: Int, totalBytes: Int) {
        self.stage = stage
        self.regionIndex = regionIndex
        self.regionCount = regionCount
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}

/// Destination des événements de progression ; vide quand on attend `value`.
struct ProgressSink: Sendable {
    private let yieldProgress: (@Sendable (OperationProgress) -> Void)?

    init<Success>(_ continuation: AsyncThrowingStream<ESPOperationEvent<Success>, any Error>.Continuation) {
        yieldProgress = { continuation.yield(.progress($0)) }
    }

    private init() { yieldProgress = nil }

    /// Ne transmet rien : pour `value`.
    static let discarding = ProgressSink()

    func report(_ progress: OperationProgress) {
        yieldProgress?(progress)
    }
}

/// Vue « progression seule » d'une opération.
private struct ProgressOnly<Success: Sendable>: AsyncSequence, Sendable {
    typealias Element = OperationProgress
    typealias Failure = any Error

    let operation: ESPOperation<Success>

    func makeAsyncIterator() -> Iterator { Iterator(base: operation.makeAsyncIterator()) }

    struct Iterator: AsyncIteratorProtocol {
        typealias Element = OperationProgress
        typealias Failure = any Error

        var base: ESPOperation<Success>.Iterator

        mutating func next() async throws -> OperationProgress? {
            try await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws(any Error) -> OperationProgress? {
            while let event = try await base.next(isolation: actor) {
                if case .progress(let progress) = event { return progress }
            }
            return nil
        }
    }
}
