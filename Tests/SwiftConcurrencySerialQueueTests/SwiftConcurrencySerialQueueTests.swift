import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func countOrderingWithoutQueue() async throws {
    // This test is flakey with the default SerialExecutor on TestActor and reliable with TestExecutor
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            try await actor.incrementWithSuspension(before: 1,
                                                    after: 2)
        }
        group.addTask(priority: .low) {
            try await actor.increment()
        }
        try await group.waitForAll()
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func countOrderingWithQueue() async throws {
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            try await actor.incrementWithSuspensionOrdered(before: 1,
                                                           after: 1)
        }
        group.addTask(priority: .low) {
            try await actor.incrementOrdered()
        }
        try await group.waitForAll()
    }
}
