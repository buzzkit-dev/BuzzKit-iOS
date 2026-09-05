import BuzzKit
import Foundation

/// Every payload the SDK hands the app, kept by message id so a scenario can open or
/// dismiss the exact notification it sent, through the SDK's own handling path.
enum PayloadStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var payloads: [String: PushPayload] = [:]

    static func remember(_ payload: PushPayload) {
        guard let id = payload.messageId else { return }
        lock.lock()
        payloads[id] = payload
        lock.unlock()
    }

    static func payload(for messageId: String) -> PushPayload? {
        lock.lock()
        defer { lock.unlock() }
        return payloads[messageId]
    }
}
