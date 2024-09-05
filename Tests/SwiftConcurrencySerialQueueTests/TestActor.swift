import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
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
        try await self.queueThrowing.enqueue {
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
        try await self.queueThrowing.enqueue {
            await self._increment_Ordered()
        }
    }

    func incrementWithSuspension_Ordered() async -> Bool {
        await self.queue.enqueue {
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
        await self.queue.enqueue {
            await self._increment_Ordered()
        }
    }
    private func _increment_Ordered() async {
        count += 1
    }
    
    private func suspension() async {
        await Task.yield()
        //do {
        //    try await Task.sleep(for: .milliseconds(1200))
        //} catch {}
    }

    init() {
        let executor = TestExecutor()
        self.executor = executor
        unownedExecutor = executor.asUnownedSerialExecutor()
        executor.start()
    }
}
