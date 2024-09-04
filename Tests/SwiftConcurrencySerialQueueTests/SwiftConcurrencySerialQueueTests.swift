import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func countOrderingWithoutQueue() async throws {
    // This flakes on run repeatedly
    // Changing Task.yield in TestActor to Task.sleep makes it flake *less*
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            try await actor.incrementWithSuspension()
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
            try await actor.incrementWithSuspensionOrdered()
        }
        group.addTask(priority: .low) {
            try await actor.incrementOrdered()
        }
        try await group.waitForAll()
    }
}
