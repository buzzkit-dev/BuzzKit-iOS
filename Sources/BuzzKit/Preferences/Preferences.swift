import Foundation

extension BuzzKit {
    /// A group of topics sharing a category, in the server's order. Uncategorized
    /// topics form a group with a `nil` category.
    public struct TopicGroup: Sendable, Equatable, Identifiable {
        public var id: String { category ?? "" }
        public let category: String?
        public let topics: [Topic]

        /// Groups topics by category, preserving first-appearance order.
        public static func group(_ topics: [Topic]) -> [TopicGroup] {
            var order: [String?] = []
            var buckets: [String?: [Topic]] = [:]
            for topic in topics {
                if buckets[topic.category] == nil { order.append(topic.category) }
                buckets[topic.category, default: []].append(topic)
            }
            return order.map { TopicGroup(category: $0, topics: buckets[$0] ?? []) }
        }

        public init(category: String?, topics: [Topic]) {
            self.category = category
            self.topics = topics
        }
    }

    /// A notification channel a topic can be delivered on.
    public struct Channel: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let push = Channel(rawValue: "push")
        public static let email = Channel(rawValue: "email")

        /// The channel's name as shown to the user.
        public var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// A notification topic with the user's resolved preference per channel.
    public struct Topic: Sendable, Equatable, Identifiable {
        public var id: String { slug }
        public let slug: String
        public let name: String
        public let description: String?
        /// Groups the topic under a heading in notification settings.
        public let category: String?
        public let channels: [Channel: ChannelPreference]

        /// Whether the user receives this topic on at least one channel.
        public var isOptedIn: Bool {
            channels.values.contains { $0.isOptedIn }
        }

        init(dto: TopicDTO) {
            slug = dto.slug
            name = dto.name
            description = dto.description
            category = dto.category
            channels = Dictionary(
                uniqueKeysWithValues: dto.channels.map { key, value in
                    (Channel(rawValue: key), ChannelPreference(isOptedIn: value.optedIn, isDefault: value.isDefault))
                }
            )
        }

        /// Creates a topic by hand, for previews and custom data sources.
        public init(
            slug: String,
            name: String,
            description: String?,
            category: String? = nil,
            channels: [Channel: ChannelPreference]
        ) {
            self.slug = slug
            self.name = name
            self.description = description
            self.category = category
            self.channels = channels
        }

        /// A copy of the topic with every channel opted in or out, for optimistic UI.
        public func settingAllChannels(optedIn: Bool) -> Topic {
            Topic(
                slug: slug,
                name: name,
                description: description,
                category: category,
                channels: channels.mapValues { _ in
                    ChannelPreference(isOptedIn: optedIn, isDefault: false)
                }
            )
        }
    }

    /// The user's resolved preference on one channel of a topic.
    public struct ChannelPreference: Sendable, Equatable {
        /// Whether the user receives the topic on this channel.
        public let isOptedIn: Bool
        /// Whether this comes from the topic's default rather than an explicit choice.
        public let isDefault: Bool

        public init(isOptedIn: Bool, isDefault: Bool) {
            self.isOptedIn = isOptedIn
            self.isDefault = isDefault
        }
    }

    /// Reads and updates the user's notification preferences. This is the whole
    /// data layer of a notification-settings screen; `BuzzKitPreferencesView` is the
    /// drop-in UI over it.
    public struct Preferences: Sendable {
        let sdk: BuzzKit?

        /// The resolved topic list for the current user.
        public func all() async throws -> [Topic] {
            let (api, identity) = try context()
            return try await api.preferences(identity: identity).map(Topic.init(dto:))
        }

        /// Opts the user in or out of a topic on every channel.
        @discardableResult
        public func set(_ slug: String, enabled: Bool) async throws -> [Topic] {
            try await update([slug: .all(enabled)])
        }

        /// Opts the user in or out of a topic on one channel.
        @discardableResult
        public func set(_ slug: String, channel: Channel, enabled: Bool) async throws -> [Topic] {
            try await update([slug: .channels([channel.rawValue: enabled])])
        }

        func update(_ changes: [String: PreferenceChange]) async throws -> [Topic] {
            let (api, identity) = try context()
            return try await api.updatePreferences(changes, identity: identity).map(Topic.init(dto:))
        }

        private func context() throws -> (ClientAPI, SubscriberIdentity) {
            guard let sdk else { throw BuzzKitError.notConfigured }
            return (sdk.api, sdk.currentIdentitySnapshot())
        }
    }

    /// The user's notification preferences.
    public static var preferences: Preferences {
        Preferences(sdk: instanceIfConfigured)
    }
}
