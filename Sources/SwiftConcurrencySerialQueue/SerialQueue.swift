//
//  SerialQueue.swift
//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class SerialQueue: Sendable {
    public typealias WorkItem<Result> = @Sendable () async -> Result
    private typealias SerialStream = AsyncStream<WorkItem<Void>>
    private let continuation: SerialStream.Continuation
    private let task: Task<(), any Error>
    public init(priority: TaskPriority? = nil) {
        let (queue, continuation) = SerialStream.makeStream()
        self.continuation = continuation
        task = Task(priority: priority) {
            for try await work in queue {
                await work()
            }
        }
    }
    deinit {
        task.cancel()
    }
    public func enqueue(_ work: @escaping WorkItem<Void>) {
        continuation.yield(work)
    }
    public func enqueue<Result>(_ work: @escaping WorkItem<Result>) async -> Result {
        await withCheckedContinuation { resultContinuation in
            continuation.yield {
                resultContinuation.resume(returning: await work())
            }
        }
    }
}
