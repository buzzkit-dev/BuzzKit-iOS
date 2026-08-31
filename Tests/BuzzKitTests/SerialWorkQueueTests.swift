import Foundation
import Testing
@testable import BuzzKit

@Suite struct SerialWorkQueueTests {
    @Test func runsWorkInSubmissionOrder() async {
        let queue = SerialWorkQueue()
        let order = LockedState<[Int]>([])
        for index in 0..<20 {
            queue.enqueue {
                if index.isMultiple(of: 3) {
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                order.withLock { $0.append(index) }
            }
        }
        await queue.drain()
        #expect(order.read() == Array(0..<20))
    }

    @Test func laterEnqueueWaitsForEarlierSlowWork() async {
        let queue = SerialWorkQueue()
        let log = LockedState<[String]>([])
        queue.enqueue {
            try? await Task.sleep(nanoseconds: 20_000_000)
            log.withLock { $0.append("logout") }
        }
        queue.enqueue {
            log.withLock { $0.append("identify") }
        }
        await queue.drain()
        #expect(log.read() == ["logout", "identify"])
    }
}
