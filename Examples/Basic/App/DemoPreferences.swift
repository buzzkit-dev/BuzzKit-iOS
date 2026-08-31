import BuzzKit
import Foundation

final class DemoPreferences: @unchecked Sendable {
    static let shared = DemoPreferences()
    private let lock = NSLock()
    private var topics: [BuzzKit.Topic] = [
        BuzzKit.Topic(
            slug: "gym-reminders",
            name: "Gym reminders",
            description: "Nudges when your streak is at risk.",
            category: "Training",
            channels: [.push: .init(isOptedIn: true, isDefault: true)]
        ),
        BuzzKit.Topic(
            slug: "digest",
            name: "Weekly digest",
            description: "Your training week, summarized.",
            category: "Training",
            channels: [
                .push: .init(isOptedIn: true, isDefault: true),
                .email: .init(isOptedIn: true, isDefault: true),
            ]
        ),
        BuzzKit.Topic(
            slug: "deals",
            name: "Deals",
            description: "Discounts and seasonal offers.",
            category: "From us",
            channels: [
                .push: .init(isOptedIn: false, isDefault: false),
                .email: .init(isOptedIn: true, isDefault: true),
            ]
        ),
        BuzzKit.Topic(
            slug: "product-updates",
            name: "Product updates",
            description: nil,
            category: "From us",
            channels: [.email: .init(isOptedIn: true, isDefault: true)]
        ),
    ]

    func all() -> [BuzzKit.Topic] {
        lock.lock()
        defer { lock.unlock() }
        return topics
    }

    func set(_ slug: String, enabled: Bool) -> [BuzzKit.Topic] {
        lock.lock()
        defer { lock.unlock() }
        topics = topics.map { topic in
            topic.slug == slug ? topic.settingAllChannels(optedIn: enabled) : topic
        }
        return topics
    }

    func set(_ slug: String, channel: BuzzKit.Channel, enabled: Bool) -> [BuzzKit.Topic] {
        lock.lock()
        defer { lock.unlock() }
        topics = topics.map { topic in
            guard topic.slug == slug else { return topic }
            var channels = topic.channels
            channels[channel] = .init(isOptedIn: enabled, isDefault: false)
            return BuzzKit.Topic(
                slug: topic.slug,
                name: topic.name,
                description: topic.description,
                category: topic.category,
                channels: channels
            )
        }
        return topics
    }
}
