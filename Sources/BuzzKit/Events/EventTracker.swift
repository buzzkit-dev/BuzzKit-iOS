import Foundation

struct EventTracker: Sendable {
    let queue: EventQueue
    let identity: IdentityStore
    let logger: BKLogger

    func track(_ name: String, data: [String: JSONValue]? = nil, timestamp: Date = Date()) async {
        guard EventNames.isValidCustomName(name) else {
            logger.error("Ignoring event with invalid name '\(name)'; custom names cannot start with $")
            return
        }
        await record(name: name, data: data, timestamp: timestamp)
    }

    func trackSystem(_ name: String, data: [String: JSONValue]? = nil, timestamp: Date = Date()) async {
        guard EventNames.reserved.contains(name) else {
            logger.error("Ignoring unknown system event '\(name)'")
            return
        }
        await record(name: name, data: data, timestamp: timestamp)
    }

    private func record(name: String, data: [String: JSONValue]?, timestamp: Date) async {
        let current = await identity.current
        await queue.enqueue(
            QueuedEvent(
                id: UUID().uuidString.lowercased(),
                externalId: current.externalId,
                identityHash: current.identityHash,
                name: name,
                data: data,
                timestamp: timestamp
            )
        )
        await queue.scheduleFlush()
    }
}
