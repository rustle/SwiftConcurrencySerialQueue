//
//  SerialQueueThrowing.swift
//

import Foundation
import Synchronization

/// Hopefully legible mental models for paths through the labyrinth
///
/// The happy path:
/// * Enqueue some work
/// * Create an entry tracked by a generated id with a .waiting value in states
/// * Hop through a couple awaits to get a cancellation handler and a continuation
/// * Check if the entry we placed in .states is still a .waiting
/// * Yay it is, replace it with a .active
/// * Create EnqueuedWorkItem and yield it to our async stream
/// * When our work item is actually executed (see init for where we await for our async stream to yield) we end up in the execute closure
/// * Remove our entry in .states (last time we saw it, it was .waiting)
/// * Check our entry again to see if we're still a .active
/// * Yay it is is, go ahead and await the work that was enqueued
/// * One last check for cancellation, we weren't cancelled this time
/// * Resume returning result returned from work
///
/// Cancelled while waiting to enqueue:
/// * Enqueue some work
/// * Place a .waiting in states tracked by a generated id
/// * Happening Concurrently:
///     * onCancelled runs
///         * Remove our entry in .states (last time we saw it, it was .waiting)
///         * Check if our entry has become an .active (meaning it's been successfully enqueued in our async stream)
///         * It's not, we're done. Removing the entry lets our enqueue logic know not to proceed.
///     * *Hop through a couple awaits to get a cancellation handler and a continuation
///         * Check if the .waiting we placed in .states is still a .waiting, nope, it's something else now
///         * Remove entry in states and resume throwing a CancellationError
///
/// Cancelled after being enqueued but before awaiting our work closure inside our execute closure:
/// * Enqueue some work
/// * Place a .waiting in states tracked by a generated id
/// * Happening Concurrently:
///     * onCancelled runs
///         * Remove our entry tracked by our generated id (last time we saw it, it was .waiting)
///         * Check if our entry has become an .active (meaning it's been successfully enqueued in our async stream)
///         * It has, use it's associated value to resume throwing a CancellationError (the resume is in a Task but for our purpose here that's incidental)
///     * *Hop through a couple awaits to get a cancellation handler and a continuation
///         * Check if the .waiting we placed in .states is still a .waiting
///         * Yay it is, replace it with a .active
///         * Create EnqueuedWorkItem and yield it to our async stream
///         * When our work item is actually executed (see init for where we await for our async stream to yield) we end up in the execute closure
///         * Remove our entry in .states (last time we saw it, it was .active)
///         * Check our entry again to see if we're still a .active
///         * It's not, we're all done (onCancelled has handled the resume throwing CancellationError)
///
/// The remaining paths are just awaiting work, passing any errors to resume throwing
/// then one last check for cancellation, again passing any errors to resume throwing
/// before we arrive at the happy path we started with

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class SerialQueueThrowing: @unchecked Sendable {
    public typealias WorkItem<Result: Sendable> = @Sendable (isolated (any Actor)?) async throws -> Result

    private enum State: Sendable {
        case waiting
        case active(@Sendable (Result<Any, Error>) -> Void)
        case cancelled
    }

    private struct EnqueuedWorkItem: Sendable {
        let id: UUID
        let priority: TaskPriority
        let isolation: (any Actor)?
        let execute: @Sendable () async -> Void
    }

    private let continuation: AsyncStream<EnqueuedWorkItem>.Continuation
    private let task: Task<Void, Never>
    private let states: Mutex<[UUID: State]> = .init([:])

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
    ) async throws -> Result {
        let id = UUID()
        let priority = Task.currentPriority
        self.states.withLock { states in
            states[id] = .waiting
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                let execute: @Sendable () async -> Void = { [weak self] in
                    guard let self else {
                        return
                    }
                    
                    let state = self.states.withLock { states in
                        states.removeValue(forKey: id)
                    }
                    guard case .active = state else {
                        return
                    }

                    do {
                        let value = try await work(isolation)
                        try Task.checkCancellation()
                        continuation.resume(returning: value)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }

                let shouldEnqueue = self.states.withLock { states in
                    if case .waiting = states[id] {
                        states[id] = .active { result in
                            if case .failure(let error) = result {
                                continuation.resume(throwing: error)
                            }
                        }
                        return true
                    } else {
                        states.removeValue(forKey: id)
                        continuation.resume(throwing: CancellationError())
                        return false
                    }
                }

                if shouldEnqueue {
                    self.continuation.yield(EnqueuedWorkItem(id: id,
                                                             priority: priority,
                                                             isolation: isolation,
                                                             execute: execute))
                }
            }
        } onCancel: {
            let state = self.states.withLock { states in
                states.removeValue(forKey: id)
            }
            if case .active(let resume) = state {
                resume(.failure(CancellationError()))
            }
        }
    }

    deinit {
        continuation.finish()
        task.cancel()
    }
}
