import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
actor TestActor {
    private var count = 0
    func incrementWithSuspension() async throws {
        count += 1
        let before = count
        await Task.yield()
        //try await Task.sleep(for: .milliseconds(1200))
        #expect(count != before)
    }
    func increment() async throws {
        count += 1
    }
    private let queue = SerialQueueThrowing()
    func incrementWithSuspensionOrdered() async throws {
        try await self.queue.enqueue {
            try await self._incrementWithSuspensionOrdered()
        }
    }
    func _incrementWithSuspensionOrdered() async throws {
        self.count += 1
        let before = count
        await Task.yield()
        //try await Task.sleep(for: .milliseconds(1200))
        #expect(count == before)
    }
    func incrementOrdered() async throws {
        try await self.queue.enqueue {
            try await self._incrementOrdered()
        }
    }
    func _incrementOrdered() async throws {
        count += 1
    }
    private nonisolated let executor: any SerialExecutor
    nonisolated let unownedExecutor: UnownedSerialExecutor
    init() {
        let executor = TestExecutor()
        self.executor = executor
        unownedExecutor = executor.asUnownedSerialExecutor()
        executor.start()
    }
}
