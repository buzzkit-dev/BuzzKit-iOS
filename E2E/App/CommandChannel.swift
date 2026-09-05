import ActivityKit
@_spi(BuzzKitInternal) import BuzzKit
import Foundation
import UserNotifications

/// Polls the runner for work the scenarios need the app to do. Anything a real app
/// would trigger from its own UI is driven from here so a scenario stays declarative.
enum CommandChannel {
    nonisolated(unsafe) static var collector: URL?
    nonisolated(unsafe) static var run: String = "unknown"

    static func start() {
        guard collector != nil else { return }
        Task.detached {
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private static func poll() async {
        guard let collector else { return }
        var components = URLComponents(url: collector.appendingPathComponent("commands"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "run", value: run)]
        guard let url = components?.url else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
            let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        for entry in list {
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { continue }
            await perform(id: id, name: name, arguments: entry["arguments"] as? [String: Any] ?? [:])
        }
    }

    private static func perform(id: String, name: String, arguments: [String: Any]) async {
        switch name {
        case "identify":
            BuzzKit.identify(arguments["externalId"] as? String ?? "")
            Reporter.send("command.done", ["id": id, "name": name])
        case "logout":
            BuzzKit.logout()
            Reporter.send("command.done", ["id": id, "name": name])
        case "track":
            BuzzKit.track(arguments["name"] as? String ?? "unknown")
            await settleEvents()
            Reporter.send("command.done", ["id": id, "name": name])
        case "topics":
            await report(id: id, name: name) {
                let topics = try await BuzzKit.preferences.all()
                return ["topics": topics.map(\.slug)]
            }
        case "setTopic":
            await report(id: id, name: name) {
                let slug = arguments["slug"] as? String ?? ""
                let enabled = arguments["enabled"] as? Bool ?? true
                let topics = try await BuzzKit.preferences.set(slug, enabled: enabled)
                let match = topics.first { $0.slug == slug }
                return ["slug": slug, "optedIn": match?.isOptedIn ?? false]
            }
        case "permission":
            let status = await BuzzKit.notificationPermission()
            Reporter.send("command.done", ["id": id, "name": name, "status": status.rawValue])
        case "open":
            await report(id: id, name: name) {
                let payload = try storedPayload(arguments)
                BuzzKit.openNotification(
                    payload: payload,
                    actionIdentifier: arguments["actionIdentifier"] as? String,
                    input: arguments["input"] as? String
                )
                return [:]
            }
        case "dismiss":
            await report(id: id, name: name) {
                BuzzKit.dismissNotification(payload: try storedPayload(arguments))
                return [:]
            }
        case "receive":
            let userInfo = arguments["userInfo"] as? [AnyHashable: Any] ?? [:]
            let outcome = await BuzzKit.didReceiveRemoteNotification(userInfo: userInfo)
            Reporter.send("command.done", ["id": id, "name": name, "outcome": String(describing: outcome)])
        case "flush":
            await settleEvents()
            Reporter.send("command.done", ["id": id, "name": name])
        case "setAttributes":
            let raw = arguments["attributes"] as? [String: Any] ?? [:]
            BuzzKit.setAttributes(raw.compactMapValues(jsonValue))
            await settleEvents()
            Reporter.send("command.done", ["id": id, "name": name, "keys": raw.keys.sorted()])
        case "unregisterAction":
            BuzzKit.actions.unregister(arguments["name"] as? String ?? "")
            Reporter.send("command.done", ["id": id, "name": name])
        case "setTopicChannel":
            await report(id: id, name: name) {
                let slug = arguments["slug"] as? String ?? ""
                let channel = BuzzKit.Channel(rawValue: arguments["channel"] as? String ?? "push")
                let enabled = arguments["enabled"] as? Bool ?? true
                let topics = try await BuzzKit.preferences.set(slug, channel: channel, enabled: enabled)
                let match = topics.first { $0.slug == slug }
                return ["slug": slug, "optedIn": match?.channels[channel]?.isOptedIn ?? false]
            }
        case "deliveredNotifications":
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            let listed = delivered.map { notification -> [String: Any] in
                let content = notification.request.content
                let envelope = content.userInfo["bk"] as? [String: Any]
                return [
                    "id": notification.request.identifier,
                    "title": content.title,
                    "subtitle": content.subtitle,
                    "body": content.body,
                    "badge": content.badge ?? NSNull(),
                    "attachments": content.attachments.count,
                    "messageId": envelope?["messageId"] as? String ?? NSNull(),
                ]
            }
            Reporter.send("command.done", ["id": id, "name": name, "delivered": listed])
        case "pendingLocalNotifications":
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let listed = requests.map { request -> [String: Any] in
                [
                    "id": request.identifier,
                    "title": request.content.title,
                    "body": request.content.body,
                    "userInfo": request.content.userInfo.map { "\($0.key)=\($0.value)" }.sorted(),
                ]
            }
            Reporter.send("command.done", ["id": id, "name": name, "pending": listed])
        case "observeActivities":
            BuzzKit.activities.observe(E2EAttributes.self)
            Reporter.send("command.done", ["id": id, "name": name])
        case "startActivity":
            await report(id: id, name: name) {
                let activity = try BuzzKit.activities.start(
                    E2EAttributes(name: arguments["activityName"] as? String ?? "e2e"),
                    state: .init(status: "started", step: 0)
                )
                return ["activityId": activity.id]
            }
        case "activities":
            let listed = Activity<E2EAttributes>.activities.map { activity -> [String: Any] in
                [
                    "id": activity.id,
                    "name": activity.attributes.name,
                    "state": String(describing: activity.activityState),
                    "status": activity.content.state.status,
                    "step": activity.content.state.step,
                ]
            }
            Reporter.send("command.done", ["id": id, "name": name, "activities": listed])
        case "endActivity":
            await report(id: id, name: name) {
                let activityId = arguments["activityId"] as? String ?? ""
                guard let activity = Activity<E2EAttributes>.activities.first(where: { $0.id == activityId }) else {
                    throw CommandError.missingActivity(activityId)
                }
                let immediate = arguments["dismissal"] as? String == "immediate"
                await BuzzKit.activities.end(activity, dismissalPolicy: immediate ? .immediate : .default)
                return ["activityId": activityId, "dismissal": immediate ? "immediate" : "default"]
            }
        default:
            Reporter.send("command.failed", ["id": id, "name": name, "error": "unknown command"])
        }
    }

    /// `track` hands off to a detached task, so a flush issued straight after it can run
    /// before the event is even queued. Wait for the queue to show the event, then drain it.
    private static func settleEvents() async {
        for _ in 0..<20 where await BuzzKit.pendingEventCount() == 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await BuzzKit.flushEvents()
        for _ in 0..<20 where await BuzzKit.pendingEventCount() > 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await BuzzKit.flushEvents()
        }
    }

    /// The runner sends plain JSON; the SDK wants its typed value. Only the shapes the
    /// scenarios use are mapped.
    private static func jsonValue(_ any: Any) -> JSONValue? {
        switch any {
        case let string as String: return JSONValue(stringLiteral: string)
        case let bool as Bool: return JSONValue(booleanLiteral: bool)
        case let int as Int: return JSONValue(integerLiteral: int)
        case let double as Double: return JSONValue(floatLiteral: double)
        default: return nil
        }
    }

    private static func storedPayload(_ arguments: [String: Any]) throws -> PushPayload {
        let messageId = arguments["messageId"] as? String ?? ""
        guard let payload = PayloadStore.payload(for: messageId) else {
            throw CommandError.unknownMessage(messageId)
        }
        return payload
    }

    private static func report(
        id: String,
        name: String,
        work: () async throws -> [String: Any]
    ) async {
        do {
            var fields = try await work()
            fields["id"] = id
            fields["name"] = name
            Reporter.send("command.done", fields)
        } catch {
            Reporter.send("command.failed", ["id": id, "name": name, "error": String(describing: error)])
        }
    }
}

enum CommandError: Error, CustomStringConvertible {
    case unknownMessage(String)
    case missingActivity(String)

    var description: String {
        switch self {
        case .unknownMessage(let id): return "no payload received for message \(id)"
        case .missingActivity(let id): return "no live activity with id \(id)"
        }
    }
}
