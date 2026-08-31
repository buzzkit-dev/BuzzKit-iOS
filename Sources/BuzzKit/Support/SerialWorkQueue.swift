import Foundation

final class SerialWorkQueue: Sendable {
    private let tail = LockedState<Task<Void, Never>?>(nil)

    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        tail.withLock { previous in
            let earlier = previous
            previous = Task {
                await earlier?.value
                await work()
            }
        }
    }

    func drain() async {
        await tail.read()?.value
    }
}
