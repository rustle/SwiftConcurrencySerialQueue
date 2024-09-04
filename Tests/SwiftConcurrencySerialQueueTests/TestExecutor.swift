import Foundation
import os

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public final class TestExecutor: Thread, SerialExecutor, @unchecked Sendable {
    public override init() {
        super.init()
        name = "RunLoopExecutor"
        qualityOfService = .default
    }
    public override func main() {
        autoreleasepool {
            // Toss something on the run loop so it doesn't return right away
            Timer.scheduledTimer(
                timeInterval: Date.distantFuture.timeIntervalSince1970,
                target: self,
                selector: #selector(nop),
                userInfo: nil,
                repeats: true
            )
            while true {
                autoreleasepool {
                    _ = RunLoop.current
                        .run(
                            mode: .default,
                            before: Date(timeIntervalSinceNow: 1.0)
                        )
                }
            }
        }
    }
    @objc private func nop() {}
    private let jobs = OSAllocatedUnfairLock<[UInt8: [UnownedJob]]>(initialState: [:])
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        jobs.withLock { jobs in
            jobs[job.priority.rawValue, default: []].append(job)
        }
        run()
    }
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
    private func run() {
        perform(#selector(enqueueOnRunLoop),
                on: self,
                with: nil,
                waitUntilDone: false,
                modes: [RunLoop.Mode.default.rawValue])
    }
    @objc private func coalesce() {
        Self.cancelPreviousPerformRequests(withTarget: self,
                                           selector: #selector(enqueueOnRunLoop),
                                           object: nil)
        perform(#selector(enqueueOnRunLoop),
                with: nil,
                afterDelay: 1.0)
    }
    @objc private func enqueueOnRunLoop() {
        guard let job = jobs.withLock({ jobs in
            guard !jobs.isEmpty else {
                return nil as UnownedJob?
            }
            func dequeue(priority: TaskPriority) -> UnownedJob? {
                guard var jobsForPriority = jobs[priority.rawValue] else {
                    return nil
                }
                guard !jobsForPriority.isEmpty else {
                    return nil
                }
                let job = jobsForPriority.removeFirst()
                jobs[priority.rawValue] = jobsForPriority
                return job
            }
            if let job = dequeue(priority: .high) {
                return job
            }
            if let job = dequeue(priority: .low) {
                return job
            }
            fatalError("Unsupported Priority on TestExecutor")
        }) else {
            return
        }
        job.runSynchronously(on: asUnownedSerialExecutor())
    }
}
