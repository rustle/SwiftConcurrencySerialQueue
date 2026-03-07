import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 15.0, iOS 18.0, watchOS 10.0, tvOS 18.0, *)
actor TestActor {
    private var count = 0
    private let queueThrowing = SerialQueueThrowing()
    private let queue = SerialQueue()
    private nonisolated let executor: any SerialExecutor
    nonisolated let unownedExecutor: UnownedSerialExecutor

    func incrementWithSuspension() async -> Bool {
        count += 1
        let before = count
        await suspension()
        return count != before
    }
    func increment() async {
        count += 1
    }

    func incrementWithSuspension_Throwing() async throws {
        count += 1
        let before = count
        await suspension()
        #expect(count != before)
    }
    func increment_Throwing() async throws {
        count += 1
    }

    func incrementWithSuspension_Ordered_Throwing() async throws {
        try await self.queueThrowing.enqueue { _ in
            try await self._incrementWithSuspension_Ordered_Throwing()
        }
    }
    private func _incrementWithSuspension_Ordered_Throwing() async throws {
        self.count += 1
        let before = count
        await suspension()
        #expect(count == before)
    }
    func increment_Ordered_Throwing() async throws {
        try await self.queueThrowing.enqueue { _ in
            await self._increment_Ordered()
        }
    }

    func incrementWithSuspension_Ordered() async -> Bool {
        await self.queue.enqueue { _ in
            await self._incrementWithSuspension_Ordered()
        }
    }
    private func _incrementWithSuspension_Ordered() async -> Bool {
        self.count += 1
        let before = count
        await suspension()
        return count == before
    }
    func increment_Ordered() async {
        await self.queue.enqueue { _ in
            await self._increment_Ordered()
        }
    }
    private func _increment_Ordered() async {
        count += 1
    }
    
    private func suspension() async {
        await Task.yield()
    }

    init() {
        let executor = TestExecutor()
        self.executor = executor
        unownedExecutor = executor.asUnownedSerialExecutor()
        executor.start()
    }
}
