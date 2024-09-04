import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
actor TestActor {
    private var count = 0
    func incrementWithSuspension(before: Int,
                                 after: Int) async throws {
        count += 1
        #expect(count == before)
        await Task.yield()
        #expect(count == after)
    }
    func increment() async throws {
        count += 1
        #expect(count == 2)
    }
    private let queue = SerialQueueThrowing()
    func incrementWithSuspensionOrdered(before: Int,
                                        after: Int) async throws {
        try await self.queue.enqueue {
            try await self._incrementWithSuspensionOrdered(before: before,
                                                           after: after)
        }
    }
    func _incrementWithSuspensionOrdered(before: Int,
                                         after: Int) async throws {
        self.count += 1
        #expect(count == before)
        await Task.yield()
        #expect(count == after)
    }
    func incrementOrdered() async throws {
        try await self.queue.enqueue {
            try await self._incrementOrdered()
        }
    }
    func _incrementOrdered() async throws {
        count += 1
        #expect(count == 2)
    }
#if true
    private nonisolated let executor: any SerialExecutor
    nonisolated let unownedExecutor: UnownedSerialExecutor
    init() {
        let executor = TestExecutor()
        self.executor = executor
        unownedExecutor = executor.asUnownedSerialExecutor()
        executor.start()
    }
#endif
}
