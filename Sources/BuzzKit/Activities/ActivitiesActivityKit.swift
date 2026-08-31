#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

@available(iOS 16.2, *)
extension BuzzKit.Activities {
    /// Starts a Live Activity and hands it to BuzzKit in one call: requests it through
    /// ActivityKit with a push token, registers the token, and tracks
    /// `$activity.started`.
    ///
    /// ```swift
    /// let activity = try BuzzKit.activities.start(
    ///     WorkoutAttributes(workoutId: id),
    ///     state: .init(elapsed: 0)
    /// )
    /// ```
    @discardableResult
    public func start<Attributes: ActivityAttributes>(
        _ attributes: Attributes,
        state: Attributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double = 0
    ) throws -> Activity<Attributes> {
        let activity = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: staleDate, relevanceScore: relevanceScore),
            pushType: .token
        )
        monitor(activity)
        return activity
    }

    /// Watches every activity of a type, current and future, wherever it was started:
    /// by the app, by ``start(_:state:staleDate:)``, or remotely by the server. Tokens
    /// stay registered, lifecycle events are tracked, and on iOS 17.2 the push-to-start
    /// token registers too. Call once at launch per attributes type.
    public func observe<Attributes: ActivityAttributes>(_ type: Attributes.Type) {
        for activity in Activity<Attributes>.activities {
            monitor(activity, isNew: false)
        }
        Task {
            for await activity in Activity<Attributes>.activityUpdates {
                monitor(activity)
            }
        }
        if #available(iOS 17.2, *) {
            enablePushToStart(for: type)
        }
    }

    /// Ends an activity everywhere: on the device through ActivityKit, on the server,
    /// and as an `$activity.ended` event.
    public func end<Attributes: ActivityAttributes>(
        _ activity: Activity<Attributes>,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async {
        await activity.end(activity.content, dismissalPolicy: dismissalPolicy)
        try? await end(id: activity.id)
    }

    /// Keeps an activity's push token registered and its lifecycle tracked. Prefer
    /// ``observe(_:)`` or ``start(_:state:staleDate:)``, which call this for you.
    public func monitor<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>) {
        monitor(activity, isNew: true)
    }

    func monitor<Attributes: ActivityAttributes>(_ activity: Activity<Attributes>, isNew: Bool) {
        let activityId = activity.id
        let attributesType = String(describing: Attributes.self)
        guard ActivitySeen.markNew(activityId) else { return }
        if isNew {
            trackLifecycle(EventNames.activityStarted, id: activityId, attributesType: attributesType)
        }
        let boxed = UncheckedSendableBox(activity)
        Task {
            for await token in boxed.value.pushTokenUpdates {
                try? await register(id: activityId, token: token, attributesType: attributesType)
            }
        }
        Task {
            for await state in boxed.value.activityStateUpdates {
                switch state {
                case .ended:
                    trackLifecycle(EventNames.activityEnded, id: activityId, attributesType: attributesType)
                    try? await end(id: activityId)
                case .dismissed:
                    trackLifecycle(EventNames.activityDismissed, id: activityId, attributesType: attributesType)
                    try? await end(id: activityId)
                    return
                case .stale:
                    trackLifecycle(EventNames.activityStale, id: activityId, attributesType: attributesType)
                default:
                    break
                }
            }
        }
    }

    /// Registers push-to-start tokens for an attributes type, so the server can start
    /// activities of this type without the app running.
    @available(iOS 17.2, *)
    public func enablePushToStart<Attributes: ActivityAttributes>(for _: Attributes.Type) {
        let attributesType = String(describing: Attributes.self)
        Task {
            for await token in Activity<Attributes>.pushToStartTokenUpdates {
                try? await registerPushToStartToken(token, attributesType: attributesType)
            }
        }
    }
}
#endif
