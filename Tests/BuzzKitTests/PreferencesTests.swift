import Foundation
import Testing
@testable import BuzzKit

@Suite struct PreferencesTests {
    @Test func mapsTopicFromDTO() throws {
        let json = #"{"slug":"gym-reminders","name":"Gym reminders","description":"Nudges","channels":{"push":{"optedIn":true,"isDefault":false},"email":{"optedIn":false,"isDefault":true}}}"#
        let dto = try JSONCoding.decoder.decode(TopicDTO.self, from: Data(json.utf8))
        let topic = BuzzKit.Topic(dto: dto)
        #expect(topic.id == "gym-reminders")
        #expect(topic.channels[.push]?.isOptedIn == true)
        #expect(topic.channels[.push]?.isDefault == false)
        #expect(topic.channels[.email]?.isOptedIn == false)
        #expect(topic.isOptedIn)
    }

    @Test func fullyOptedOutTopicReadsFalse() throws {
        let json = #"{"slug":"digest","name":"Digest","description":null,"channels":{"push":{"optedIn":false,"isDefault":true}}}"#
        let dto = try JSONCoding.decoder.decode(TopicDTO.self, from: Data(json.utf8))
        #expect(!BuzzKit.Topic(dto: dto).isOptedIn)
    }

    @Test func encodesChannelAndWholeTopicChanges() throws {
        let body = PreferencesBody(preferences: [
            "gym": .all(false),
            "deals": .channels(["push": true]),
        ])
        let data = try JSONCoding.encoder.encode(body)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let preferences = try #require(decoded["preferences"] as? [String: Any])
        #expect(preferences["gym"] as? Bool == false)
        #expect((preferences["deals"] as? [String: Bool])?["push"] == true)
    }
}

@Suite struct TopicGroupTests {
    private func topic(_ slug: String, category: String?) -> BuzzKit.Topic {
        BuzzKit.Topic(
            slug: slug,
            name: slug,
            description: nil,
            category: category,
            channels: [.push: .init(isOptedIn: true, isDefault: true)]
        )
    }

    @Test func groupsByFirstAppearance() {
        let groups = BuzzKit.TopicGroup.group([
            topic("a", category: "Events"),
            topic("b", category: nil),
            topic("c", category: "Events"),
            topic("d", category: "From us"),
        ])
        #expect(groups.map(\.category) == ["Events", nil, "From us"])
        #expect(groups[0].topics.map(\.slug) == ["a", "c"])
        #expect(groups[1].topics.map(\.slug) == ["b"])
    }

    @Test func decodesCategoryFromDTO() throws {
        let json = #"{"slug":"x","name":"X","description":null,"category":"Events","channels":{"push":{"optedIn":true,"isDefault":true}}}"#
        let dto = try JSONCoding.decoder.decode(TopicDTO.self, from: Data(json.utf8))
        #expect(BuzzKit.Topic(dto: dto).category == "Events")
    }
}

@Suite struct DeviceContextTests {
    @Test func encodesTheDeviceSnapshot() throws {
        let store = KeyValueStore(defaults: UserDefaults(suiteName: "buzzkit-device-\(UUID().uuidString)")!)
        store.set("2026-08-30T12:00:00.000Z", for: StorageKey.installedAt)
        let context = DeviceContext.current(store: store)
        #expect(context.sdkVersion == SDKInfo.version)
        #expect(!context.osVersion.isEmpty)
        let data = try JSONCoding.encoder.encode(context)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["sdkVersion"] as? String == SDKInfo.version)
        #expect(decoded["installedAt"] as? String == "2026-08-30T12:00:00.000Z")
        #expect(!(decoded["locale"] as? String ?? "").isEmpty)
    }
}
