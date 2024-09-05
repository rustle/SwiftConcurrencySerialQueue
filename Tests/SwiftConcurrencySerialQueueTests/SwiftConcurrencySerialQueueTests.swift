import Testing
@testable import SwiftConcurrencySerialQueue

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func withoutQueue() async throws {
    // This flakes on run repeatedly
    // Changing Task.yield in TestActor to Task.sleep makes it flake *less*
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            #expect(await actor.incrementWithSuspension())
        }
        group.addTask(priority: .low) {
            await actor.increment()
        }
        try await group.waitForAll()
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func withQueue() async throws {
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            #expect(await actor.incrementWithSuspension_Ordered())
        }
        group.addTask(priority: .low) {
            await actor.increment_Ordered()
        }
        try await group.waitForAll()
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func withoutQueue_Throwing() async throws {
    // This flakes on run repeatedly
    // Changing Task.yield in TestActor to Task.sleep makes it flake *less*
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            try await actor.incrementWithSuspension_Throwing()
        }
        group.addTask(priority: .low) {
            try await actor.increment_Throwing()
        }
        try await group.waitForAll()
    }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@Test func withQueue_Throwing() async throws {
    let actor = TestActor()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(priority: .high) {
            try await actor.incrementWithSuspension_Ordered_Throwing()
        }
        group.addTask(priority: .low) {
            try await actor.increment_Ordered_Throwing()
        }
        try await group.waitForAll()
    }
}
