//
//  SerialQueueThrowing.swift
//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public final class SerialQueueThrowing: Sendable {
    public typealias WorkItem<Result> = @Sendable () async throws -> Result
    private typealias SerialStream = AsyncThrowingStream<WorkItem<Void>, Error>
    private let continuation: SerialStream.Continuation
    private let task: Task<(), any Error>
    public init(priority: TaskPriority? = nil) {
        let (queue, continuation) = SerialStream.makeStream()
        self.continuation = continuation
        task = Task(priority: priority) {
            for try await work in queue {
                try await work()
            }
        }
    }
    deinit {
        continuation.finish()
    }
    public func enqueue<Result>(_ work: @escaping WorkItem<Result>) async throws -> Result {
        try await withCheckedThrowingContinuation { resultContinuation in
            continuation.yield {
                do {
                    resultContinuation.resume(returning: try await work())
                } catch {
                    resultContinuation.resume(throwing: error)
                }
            }
        }
    }
}
