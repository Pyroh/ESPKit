// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Long-running operation on the chip: write, read, verify, erase.
///
/// The operation is **cold**: nothing is sent to the chip until it is iterated
/// or `value` is awaited, and each iteration runs it again.
/// It runs in the isolation of the `ESPDevice`, so after the other operations.
///
/// - Cancelling the iterating task, or leaving the loop, stops the operation at the next block;
///   the iteration then throws `CancellationError`.
/// - `.progress` events never block the transfer: if the consumer is slower than the chip,
///   only the most recent progress is kept. `.finished` is never
///   lost.
public struct ESPOperation<Success: Sendable>: AsyncSequence, Sendable {
    public typealias Element = ESPOperationEvent<Success>
    public typealias Failure = any Error

    private let body: @Sendable (ProgressSink) async throws -> Success

    init(_ body: @escaping @Sendable (ProgressSink) async throws -> Success) {
        self.body = body
    }

    /// Runs the operation to completion without following its progress.
    public var value: Success {
        get async throws { try await body(ProgressSink.discarding) }
    }

    /// Progress only. The result is discarded: use it when `Success == Void`
    /// or when the result is read elsewhere.
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
                // With a one-element buffer, `.finished` replaces any unread progress.
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

        /// Events arrive in the caller's isolation (the main actor for a UI).
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(any Error) -> Element? {
            guard !finished else { return nil }
            // A cancelled task always throws CancellationError, even if the operation had time
            // to finish: the caller no longer waits for its result.
            if Task.isCancelled {
                finished = true
                throw CancellationError()
            }
            let event = try await base.next(isolation: actor)
            switch event {
            case .finished:
                finished = true
            case .progress:
                break
            case nil:
                // Stream finished without a result: the caller was cancelled.
                finished = true
                throw CancellationError()
            }
            return event
        }
    }
}

public enum ESPOperationEvent<Success: Sendable>: Sendable {
    case progress(OperationProgress)
    /// Always the last event of a successful iteration.
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

/// Destination of progress events; empty when awaiting `value`.
struct ProgressSink: Sendable {
    private let yieldProgress: (@Sendable (OperationProgress) -> Void)?

    init<Success>(_ continuation: AsyncThrowingStream<ESPOperationEvent<Success>, any Error>.Continuation) {
        yieldProgress = { continuation.yield(.progress($0)) }
    }

    private init() { yieldProgress = nil }

    /// Forwards nothing: for `value`.
    static let discarding = ProgressSink()

    func report(_ progress: OperationProgress) {
        yieldProgress?(progress)
    }
}

/// "Progress only" view of an operation.
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
