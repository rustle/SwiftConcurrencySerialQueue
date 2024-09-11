# SwiftConcurrencySerialQueue

Reference implementation of a queue showing how to ensure each async work item begins and ends it's work before starting it's next async work item.

My goals in building this queue are to have a simple as possible implementation, with easy to understand tests, that capture a commmon to encounter, but subtle issue in Swift Concurrency. I am optimistic we'll get something similar to this in the standard library in the near to middle term, but in the mean time, if you're building something new, this implementation should give you the tools to handle that task.

If you want a queue implementation that is more featureful, check out [Queue](https://github.com/mattmassicotte/Queue) or [swift-async-queue](https://github.com/dfed/swift-async-queue).

# The Problem

`Actor` in Swift gives us a solution to data races. State held by an `Actor` can't be mutated unsafely (concurrently, from more than 1 thread or queue, etc). Easy peasy.

BUT `Actor` carries over a trap we might expect to have been fixed with data races (it might even make it easier to fall into said trap!). **It is very easy to write code that implicitly depends on executing in the order you read it in your source code.**

```swift
actor Counter {
    private static let data = ["A", "B", "C"]
    private var cursor = 0
    func update() async throws {
        cursor += 1
        await Task.yield()
        debugPrint(Self.data[cursor % Self.data.count])
    }
}

let counter = Counter()
// cursor is 0
try await counter.update()
// cursor is 1
// prints "B"
try await counter.update()
// cursor is 2
// prints "C"
```

This code looks very reasonable and if you run it in many circumstances it will do what you expect. With the recent addition of `@isolation(any)` it's even more likely to do what you expect if you introduce `Task`s.

Let's zoom in on `update`

```
// Section 1: begin executing. We claim exclusive access to the actor and can mutate it's cursor as needed.
cursor += 1

// Section 2
// Part 1: Suspend. We give up exclusive access to the actor and allow other work to happen at the discretion of the executor.
// ↓
await Task.yield()
//               ↑
//               Part 2: Resume executing. At the executors discretion we pick back up our work and reclaim exclusive access to the actor.

// Section 3: 
debugPrint(Self.data[cursor % Self.data.count])
```

In between Part 1 and Part 2 we're allowed to do other work and that's where we can get into trouble.

Two async calls into `update` from the same context would be valid to execute using

**Order 1**
```
// Call 1 - Section 1 
    cursor == 1
// Call 1 - Section 2 - Part 1
    cursor == 1
// Call 1 - Section 2 - Part 2
    cursor == 1
// *******************************
// Call 1 - Section 3
    cursor == 1
    print "B"
// *******************************
// Call 2 - Section 1
    cursor == 2
// Call 2 - Section 2 - Part 1
    cursor == 2
// Call 2 - Section 2 - Part 2
    cursor == 2
// Call 2 - Section 3
    cursor == 2
    print "C"
```

**OR**

**Order 2**
```
// Call 1 - Section 1 
    cursor == 1
// Call 1 - Section 2 - Part 1
    cursor == 1
// Call 2 - Section 1
    cursor == 2
// Call 2 - Section 2 - Part 1
    cursor == 2
// Call 1 - Section 2 - Part 2
    cursor == 2
// *******************************
// Call 1 - Section 3
    cursor == 2
    print "C"
// *******************************
// Call 2 - Section 2 - Part 2
    cursor == 2
// Call 2 - Section 3
    cursor == 2
    print "C"
```

# Let's Fix It

We could audit our code and make sure we don't suspend in between loading and using our cursor, but the language/compiler/runtime aren't going to give us much help getting that right. Instead we'll do something that will give us at least some help.

A pretty straightforward, if verbose, way to ensure that a given async call will both begin and end before the next async call is made if we pass them to an `AsyncSequence`.

```swift
actor Counter {
    private static let data = ["A", "B", "C"]
    private var cursor = 0
    private let continuation: AsyncThrowingStream<@Sendable () async throws -> Void, Error>.Continuation
    private let task: Task<(), any Error>
    init() {
        let (queue, continuation) = AsyncThrowingStream<@Sendable () async throws -> Void, Error>.makeStream()
        self.continuation = continuation
        task = Task {
            for try await work in queue {
                try await work()
            }
        }
    }
    deinit {
        continuation.finish()
    }
    private func enqueue(_ work: @escaping @Sendable () async throws -> Void) async throws {
        try await withCheckedThrowingContinuation { resultContinuation in
            continuation.yield {
                do {
                    try await work()
                    resultContinuation.resume(returning: ())
                } catch {
                    resultContinuation.resume(throwing: error)
                }
            }
        }
    }
    func orderedUpdate() async {
        cursor += 1
        await Task.yield()
        debugPrint(Self.data[cursor % Self.data.count])
    }
    func update() async throws {
        try await enqueue {
            await self.orderedUpdate()
        }
    }
}

let counter = Counter()
// cursor is 0
try await counter.update()
// cursor is 1
// prints "B"
try await counter.update()
// cursor is 2
// prints "C"
```

The output looks the same in the common case, but now you can know you'll deterministically see Order 1 when calling `update`.

# SerialQueue

We can box up all of that verbosity in a couple straightforward types:

* `SerialQueue`
* `SerialQueueThrowing`

```swift
actor Counter {
    private static let data = ["A", "B", "C"]
    private var cursor = 0
    private let queue = SerialQueueThrowing()
    func orderedUpdate() async {
        cursor += 1
        await Task.yield()
        debugPrint(Self.data[cursor % Self.data.count])
    }
    func update() async throws {
        try await queue.enqueue {
            await self.orderedUpdate()
        }
    }
}
```

That's all well and good but the reason I built any of this is for the **tests**. I've implemented a `SerialExecutor` that behaves predictably enough with regards to ordering it's jobs that I can write a straight forward negative test case. You can see tests with and without ordering where unexpected mutation happens reliably without ordering and **never** happens with ordering. Without a negative test case it's much harder to know that we've made something that fixes a real problem.

You can drop `SerialQueue` into your project simply enough, but my hope is that the standard library is going to give us a built in solution. In the mean time, my recommendation is to see this as a way to learn the ins and out of a useful pattern and to build a solution that fits your project, migrating to the standard library implementation when it (fingers crossed) appears.