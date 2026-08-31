import Foundation

struct SessionEvent: Sendable, Equatable {
    let name: String
    let data: [String: JSONValue]?
    let timestamp: Date
}

struct SessionClock: Sendable {
    static let resumeThreshold: TimeInterval = 30

    private(set) var sessionStartedAt: Date?
    private(set) var backgroundedAt: Date?

    mutating func foregrounded(at now: Date = Date()) -> [SessionEvent] {
        if let backgroundedAt, sessionStartedAt != nil, now.timeIntervalSince(backgroundedAt) < Self.resumeThreshold {
            self.backgroundedAt = nil
            return []
        }
        var events: [SessionEvent] = []
        if let sessionStartedAt, let backgroundedAt {
            events.append(sessionEnd(startedAt: sessionStartedAt, endedAt: backgroundedAt))
        }
        sessionStartedAt = now
        backgroundedAt = nil
        events.append(SessionEvent(name: EventNames.appOpened, data: nil, timestamp: now))
        return events
    }

    mutating func backgrounded(at now: Date = Date()) -> [SessionEvent] {
        guard sessionStartedAt != nil else { return [] }
        backgroundedAt = now
        return [SessionEvent(name: EventNames.appBackgrounded, data: nil, timestamp: now)]
    }

    private func sessionEnd(startedAt: Date, endedAt: Date) -> SessionEvent {
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        return SessionEvent(
            name: EventNames.sessionEnded,
            data: ["durationSec": .number((duration * 10).rounded() / 10)],
            timestamp: endedAt
        )
    }
}
