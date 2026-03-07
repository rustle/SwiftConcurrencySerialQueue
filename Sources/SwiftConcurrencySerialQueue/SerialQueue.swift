//
//  SerialQueue.swift
//

import Foundation

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class SerialQueue: @unchecked Sendable {
    public typealias WorkItem<Result: Sendable> = @Sendable (isolated (any Actor)?) async -> Result

    private struct EnqueuedWorkItem: Sendable {
        let id: UUID
        let priority: TaskPriority
        let isolation: (any Actor)?
        let execute: @Sendable () async -> Void
    }

    private let continuation: AsyncStream<EnqueuedWorkItem>.Continuation
    private let task: Task<Void, Never>

    public init() {
        let (queue, continuation) = AsyncStream<EnqueuedWorkItem>.makeStream()
        self.continuation = continuation
        task = Task {
            for await item in queue {
                await Task(priority: item.priority) {
                    await item.execute()
                }.value
            }
        }
    }

    public func enqueue<Result: Sendable>(
        @_inheritActorContext _ work: @escaping WorkItem<Result>,
        _ isolation: (any Actor)? = #isolation
    ) async -> Result {
        let id = UUID()
        let priority = Task.currentPriority

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
            let execute: @Sendable () async -> Void = {
                continuation.resume(returning: await work(isolation))
            }
            self.continuation.yield(EnqueuedWorkItem(id: id,
                                                     priority: priority,
                                                     isolation: isolation,
                                                     execute: execute))
        }
    }

    deinit {
        continuation.finish()
        task.cancel()
    }
}
