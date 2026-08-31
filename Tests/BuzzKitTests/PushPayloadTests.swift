import Foundation
import Testing
@testable import BuzzKit

@Suite struct PushPayloadTests {
    @Test func parsesFullEnvelope() throws {
        let payload = try #require(PushPayload(userInfo: [
            "aps": ["alert": ["title": "Hey"]],
            "bk": [
                "messageId": "msg_1",
                "deepLink": "app://offers/42",
                "action": ["name": "show_offer", "data": ["offerId": "off_9"]],
                "image": "https://cdn.example.com/a.png",
            ],
            "plan": "pro",
        ]))
        #expect(payload.messageId == "msg_1")
        #expect(payload.deepLink == URL(string: "app://offers/42"))
        #expect(payload.action?.name == "show_offer")
        #expect(payload.action?.data["offerId"] == .string("off_9"))
        #expect(payload.imageURL == URL(string: "https://cdn.example.com/a.png"))
        #expect(payload.data == ["plan": .string("pro")])
    }

    @Test func fallsBackToRootKeys() throws {
        let payload = try #require(PushPayload(userInfo: [
            "aps": ["alert": "hi"],
            "messageId": "msg_2",
            "imageUrl": "https://cdn.example.com/b.png",
        ]))
        #expect(payload.messageId == "msg_2")
        #expect(payload.imageURL == URL(string: "https://cdn.example.com/b.png"))
        #expect(payload.data.isEmpty)
    }

    @Test func rejectsForeignPushes() {
        #expect(PushPayload(userInfo: ["aps": ["alert": "hi"], "other": 1]) == nil)
    }

    @Test func parsesLocalPlan() throws {
        let payload = try #require(PushPayload(userInfo: [
            "bk": [
                "local": [
                    "id": "run_1:step2",
                    "at": "2026-09-01T19:00:00",
                    "cancelOn": ["workout.completed"],
                    "title": "Time to move",
                    "body": "Your workout is waiting.",
                    "data": ["kind": "reminder"],
                ],
            ],
        ]))
        let plan = try #require(payload.localPlan)
        #expect(plan.id == "run_1:step2")
        #expect(plan.fireAt.year == 2026)
        #expect(plan.fireAt.month == 9)
        #expect(plan.fireAt.day == 1)
        #expect(plan.fireAt.hour == 19)
        #expect(plan.fireAt.minute == 0)
        #expect(plan.cancelOn == ["workout.completed"])
        #expect(plan.title == "Time to move")
        #expect(plan.data == ["kind": .string("reminder")])
    }

    @Test func parsesCancelPlan() throws {
        let payload = try #require(PushPayload(userInfo: ["bk": ["cancel": ["id": "run_1:step2"]]]))
        #expect(payload.cancelPlan?.id == "run_1:step2")
    }

    @Test func rejectsMalformedWallClock() {
        #expect(LocalNotificationPlan.wallClockComponents(from: "tomorrow") == nil)
        #expect(LocalNotificationPlan.wallClockComponents(from: "2026-09-01") == nil)
        let components = LocalNotificationPlan.wallClockComponents(from: "2026-09-01T07:30")
        #expect(components?.hour == 7)
        #expect(components?.second == 0)
    }
}

@Suite struct NotificationActionTests {
    @Test func parsesActionsAndCategory() throws {
        let payload = try #require(PushPayload(userInfo: [
            "bk": [
                "messageId": "msg_9",
                "category": "bk.abc123",
                "actions": [
                    ["id": "accept", "title": "Accept", "foreground": true],
                    ["id": "reply", "title": "Reply", "input": true, "placeholder": "Type here"],
                ],
            ],
        ]))
        #expect(payload.categoryId == "bk.abc123")
        #expect(payload.actions.count == 2)
        #expect(payload.actions[0].foreground)
        #expect(!payload.actions[0].input)
        #expect(payload.actions[1].input)
        #expect(payload.actions[1].placeholder == "Type here")
    }

    @Test func missingActionsParseEmpty() throws {
        let payload = try #require(PushPayload(userInfo: ["bk": ["messageId": "msg_1"]]))
        #expect(payload.actions.isEmpty)
        #expect(payload.categoryId == nil)
    }
}

@Suite struct InstallationTrackerTests {
    @Test func firstLaunchIsInstalled() {
        let event = InstallationTracker.event(
            previous: nil,
            current: AppRelease(version: "1.0", build: "12")
        )
        #expect(event?.name == EventNames.appInstalled)
        #expect(event?.data?["version"] == .string("1.0"))
    }

    @Test func versionChangeIsUpdated() {
        let event = InstallationTracker.event(
            previous: AppRelease(version: "1.0", build: "12"),
            current: AppRelease(version: "1.1", build: "20")
        )
        #expect(event?.name == EventNames.appUpdated)
        #expect(event?.data?["fromVersion"] == .string("1.0"))
        #expect(event?.data?["toVersion"] == .string("1.1"))
        #expect(event?.data?["toBuild"] == .string("20"))
    }

    @Test func sameReleaseIsSilent() {
        let release = AppRelease(version: "1.0", build: "12")
        #expect(InstallationTracker.event(previous: release, current: release) == nil)
    }
}

@Suite struct LocalSchedulerRegistryTests {
    private func makeScheduler() -> LocalScheduler {
        let defaults = UserDefaults(suiteName: "buzzkit-sched-\(UUID().uuidString)")!
        return LocalScheduler(store: KeyValueStore(defaults: defaults), logger: BKLogger(level: .none))
    }

    @Test func registryMapsEventsToIdsAndBack() async {
        let scheduler = makeScheduler()
        await scheduler.registerCancelEvents(["workout.completed", "app.opened"], for: "run_1:remind")
        await scheduler.registerCancelEvents(["workout.completed"], for: "run_2:nudge")
        #expect(await scheduler.cancelEvents(for: "run_1:remind") == ["app.opened", "workout.completed"])
        #expect(await scheduler.cancelEvents(for: "run_2:nudge") == ["workout.completed"])
    }

    @Test func duplicateRegistrationsStayIdempotent() async {
        let scheduler = makeScheduler()
        await scheduler.registerCancelEvents(["workout.completed"], for: "run_1:remind")
        await scheduler.registerCancelEvents(["workout.completed"], for: "run_1:remind")
        #expect(await scheduler.cancelEvents(for: "run_1:remind") == ["workout.completed"])
    }

    @Test func emptyEventListRegistersNothing() async {
        let scheduler = makeScheduler()
        await scheduler.registerCancelEvents([], for: "run_1:remind")
        #expect(await scheduler.cancelEvents(for: "run_1:remind").isEmpty)
    }
}

@Suite struct NotificationActionEdgeTests {
    @Test func defaultsAndMalformedEntries() throws {
        let payload = try #require(PushPayload(userInfo: [
            "bk": [
                "category": "bk.x",
                "actions": [
                    ["id": "plain", "title": "Plain"],
                    ["title": "No id"],
                    ["id": "no-title"],
                ],
            ],
        ]))
        #expect(payload.actions.count == 1)
        let action = try #require(payload.actions.first)
        #expect(!action.destructive && !action.foreground && !action.input)
        #expect(action.placeholder == nil)
    }
}
