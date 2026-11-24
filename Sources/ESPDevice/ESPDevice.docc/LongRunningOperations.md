# Long-Running Operations

Follow progress, get results and cancel with ``ESPOperation``.

## Overview

Writing, reading, verifying and erasing take seconds or minutes. These operations return an
``ESPOperation``, an `AsyncSequence` of ``ESPOperationEvent`` values: progress events, then a
single ``ESPOperationEvent/finished(_:)`` with the result.

An operation is *cold*: nothing reaches the chip until you iterate it or await
``ESPOperation/value``, and each iteration runs it again.

```swift
// The result only.
let data = try await esp.readFlash(at: 0, count: 0x8000).value

// Progress and result.
for try await event in esp.writeFlash(regions) {
    if case .progress(let progress) = event {
        updateBar(progress.fractionCompleted)
    }
}

// Progress only, when the result does not matter.
for try await progress in esp.eraseFlash().progress {
    print(progress.stage)
}
```

### Progress

``OperationProgress`` gives the ``OperationProgress/stage``, the region in progress and the bytes
done. Progress never slows the transfer: if the consumer is slower than the chip, only the most
recent progress is kept. The final event is never dropped. Events arrive in the caller's isolation,
so a `@MainActor` loop can update a view directly.

### Cancellation

Cancel the task that iterates, or leave the loop early: the operation stops at the next block and
the iteration throws `CancellationError`. The flash is then partly written and the chip stays in
the stub, ready for the next operation.

### Ordering

Operations run in the actor's isolation, one after the other. Starting two from different tasks
is safe: the second waits for the first.
