import Foundation
import Testing
@testable import BuzzKit

@Suite struct SpilloverTests {
    private func makeStore() -> KeyValueStore {
        KeyValueStore(defaults: UserDefaults(suiteName: "buzzkit-spill-\(UUID().uuidString)")!)
    }

    @Test func appendsAndDrains() {
        let store = makeStore()
        let entry = Spillover.Entry(
            id: "evt_1",
            externalId: "user_1",
            identityHash: nil,
            name: EventNames.notificationDelivered,
            data: ["messageId": .string("msg_1")],
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        Spillover.append(entry, to: store)
        let drained = Spillover.drain(from: store)
        #expect(drained.count == 1)
        #expect(drained[0].id == "evt_1")
        #expect(drained[0].queued.name == EventNames.notificationDelivered)
        #expect(Spillover.drain(from: store).isEmpty)
    }

    @Test func capsTheQueue() {
        let store = makeStore()
        for index in 0..<(Spillover.limit + 20) {
            Spillover.append(
                Spillover.Entry(
                    id: "evt_\(index)",
                    externalId: "user_1",
                    identityHash: nil,
                    name: EventNames.notificationDelivered,
                    data: nil,
                    timestamp: Date()
                ),
                to: store
            )
        }
        #expect(Spillover.drain(from: store).count == Spillover.limit)
    }
}
