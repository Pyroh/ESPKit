// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// An `AsyncSequence` of progress events, then the result, of a long operation on the chip:
/// write, read, verify, erase.
///
/// Iterate the operation itself to follow its progress and get its result. Each iteration
/// yields ``ESPOperationEvent/progress(_:)`` events, then a single
/// ``ESPOperationEvent/finished(_:)`` with the result:
///
/// ```swift
/// for try await event in esp.writeFlash(regions) {
///     switch event {
///     case .progress(let progress):
///         print(progress.stage, progress.fractionCompleted)
///     case .finished(let report):
///         print(report.regions.count, "regions written")
///     }
/// }
/// ```
///
/// Two shortcuts cover the cases where only one of them matters: ``value`` runs the operation and
/// returns its result, ``progress`` yields its progress and drops the result.
///
/// The operation is **cold**: nothing is sent to the chip until it is iterated or ``value`` is
/// awaited, and each iteration runs it again. Iterating ``progress`` then awaiting ``value``
/// therefore runs the operation twice: to get both, iterate the operation once.
/// It runs in the isolation of the `ESPDevice`, so after the other operations.
///
/// - Cancelling the iterating task, or leaving the loop, stops the operation at the next block;
///   the iteration then throws `CancellationError`.
/// - `.progress` events never block the transfer: if the consumer is slower than the chip,
///   only the most recent progress is kept. `.finished` is never lost.
public struct ESPOperation<Success: Sendable>: AsyncSequence, Sendable {
    /// Progress events, then the result.
    public typealias Element = ESPOperationEvent<Success>
    /// Any of the errors the operation documents, or `CancellationError`.
    public typealias Failure = any Error

    private let body: @Sendable (ProgressSink) async throws -> Success

    init(_ body: @escaping @Sendable (ProgressSink) async throws -> Success) {
        self.body = body
    }

    /// Runs the operation to completion without following its progress, and returns its result.
    ///
    /// Each access runs the operation again.
    public var value: Success {
        get async throws { try await body(ProgressSink.discarding) }
    }

    /// The progress of a new run of the operation, without its result.
    ///
    /// Use it when the operation returns nothing (`Success == Void`, as for an erase) or when the
    /// result does not matter. Awaiting ``value`` afterwards would run the operation a second
    /// time: to get both, iterate the operation itself.
    public var progress: some AsyncSequence<OperationProgress, any Error> & Sendable {
        ProgressOnly(operation: self)
    }

    /// Starts a new run of the operation. `for try await` calls it; you do not need to.
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

    /// Iterator of one run of the operation.
    public struct Iterator: AsyncIteratorProtocol {
        /// Progress events, then the result.
        public typealias Element = ESPOperationEvent<Success>
        /// Any of the errors the operation documents, or `CancellationError`.
        public typealias Failure = any Error

        var base: AsyncThrowingStream<Element, any Error>.Iterator
        var finished = false

        /// The next event; `nil` after ``ESPOperationEvent/finished(_:)``.
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

/// What an ``ESPOperation`` yields.
public enum ESPOperationEvent<Success: Sendable>: Sendable {
    /// Where the operation stands. Intermediate ones may be skipped by a slow consumer.
    case progress(OperationProgress)
    /// Always the last event of a successful iteration.
    case finished(Success)
}

/// Progress of an ``ESPOperation``.
public struct OperationProgress: Hashable, Sendable {
    /// What the operation is doing.
    public enum Stage: Hashable, Sendable {
        /// Validating, patching headers, attaching the flash.
        case preparing
        /// Erasing the whole flash (`eraseAll`, `eraseFlash`).
        case erasing
        /// Sending data to the flash.
        case writing
        /// Comparing MD5 digests, or reading back to find the differences.
        case verifying
        /// Reading flash or memory.
        case reading
    }

    /// Current stage.
    public var stage: Stage
    /// Index of the region in progress, from 0.
    public var regionIndex: Int
    /// Number of regions of the operation.
    public var regionCount: Int
    /// Bytes done across all regions (uncompressed).
    public var completedBytes: Int
    /// Bytes of the whole operation (uncompressed).
    public var totalBytes: Int

    /// `completedBytes / totalBytes`, between 0 and 1.
    public var fractionCompleted: Double {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0
    }

    /// A progress value; ESPKit creates these, the initializer is for tests and previews.
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
