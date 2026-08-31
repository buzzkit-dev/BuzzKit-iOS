import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

actor SessionTracker {
    private let tracker: EventTracker
    private let onBackground: (@Sendable () async -> Void)?
    private var clock = SessionClock()
    private var observers: [NSObjectProtocol] = []

    init(tracker: EventTracker, onBackground: (@Sendable () async -> Void)? = nil) {
        self.tracker = tracker
        self.onBackground = onBackground
    }

    func start() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
                Task { await BuzzKit.instanceIfConfigured?.sessionTracker.foregrounded() }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
                Task { await BuzzKit.instanceIfConfigured?.sessionTracker.backgrounded() }
            }
        )
        #endif
        Task { await foregrounded() }
    }

    func foregrounded(at now: Date = Date()) async {
        await emit(clock.foregrounded(at: now))
    }

    func backgrounded(at now: Date = Date()) async {
        await emit(clock.backgrounded(at: now))
        await onBackground?()
    }

    private func emit(_ events: [SessionEvent]) async {
        for event in events {
            await tracker.trackSystem(event.name, data: event.data, timestamp: event.timestamp)
        }
    }
}
