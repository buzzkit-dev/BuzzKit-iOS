import BuzzKit
import SwiftUI

/// The drop-in notification-settings screen: the user's topics with a toggle each,
/// loaded from and saved to BuzzKit.
///
/// ```swift
/// NavigationStack {
///     BuzzKitPreferencesView()
///         .navigationTitle("Notifications")
/// }
/// ```
///
/// The default row shows the topic's name and description. Pass a row builder to fully
/// own the look while keeping the loading, saving, and error handling:
///
/// ```swift
/// BuzzKitPreferencesView { topic, isOptedIn in
///     Toggle(topic.name, isOn: isOptedIn)
/// }
/// ```
public struct BuzzKitPreferencesView<Row: View>: View {
    private let load: @Sendable () async throws -> [BuzzKit.Topic]
    private let save: @Sendable (String, Bool) async throws -> [BuzzKit.Topic]
    private let saveChannel: (@Sendable (String, BuzzKit.Channel, Bool) async throws -> [BuzzKit.Topic])?
    private let row: (BuzzKit.Topic, Binding<Bool>) -> Row

    @State private var topics: [BuzzKit.Topic] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var writeGeneration = 0

    /// Creates the screen with a custom row for each topic.
    public init(@ViewBuilder row: @escaping (BuzzKit.Topic, Binding<Bool>) -> Row) {
        self.init(
            load: { try await BuzzKit.preferences.all() },
            save: { slug, enabled in try await BuzzKit.preferences.set(slug, enabled: enabled) },
            saveChannel: { slug, channel, enabled in
                try await BuzzKit.preferences.set(slug, channel: channel, enabled: enabled)
            },
            row: row
        )
    }

    /// Creates the screen over a custom data source: previews, a proxying backend, or
    /// tests. `load` returns the topics; `save` applies one change and returns the new
    /// full list; `saveChannel` applies a per-channel change and falls back to `save`
    /// when omitted.
    public init(
        load: @escaping @Sendable () async throws -> [BuzzKit.Topic],
        save: @escaping @Sendable (String, Bool) async throws -> [BuzzKit.Topic],
        saveChannel: (@Sendable (String, BuzzKit.Channel, Bool) async throws -> [BuzzKit.Topic])? = nil,
        @ViewBuilder row: @escaping (BuzzKit.Topic, Binding<Bool>) -> Row
    ) {
        self.load = load
        self.save = save
        self.saveChannel = saveChannel
        self.row = row
    }

    public var body: some View {
        List {
            if failed {
                failureRow
            } else if topics.isEmpty && !isLoading {
                Text("No notification topics yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(BuzzKit.TopicGroup.group(topics)) { group in
                    Section {
                        ForEach(group.topics) { topic in
                            if Row.self == BuzzKitTopicRow.self && topic.channels.count > 1 {
                                BuzzKitChannelRow(topic: topic) { channel, enabled in
                                    Task { await changeChannel(topic.slug, channel: channel, to: enabled) }
                                } setAll: { enabled in
                                    Task { await change(topic.slug, to: enabled) }
                                }
                            } else {
                                row(topic, binding(for: topic))
                            }
                        }
                    } header: {
                        if let category = group.category {
                            Text(category)
                        }
                    }
                }
            }
        }
        .animation(.default, value: topics)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var failureRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your notification settings could not be loaded.")
            Button("Try again") {
                Task { await reload() }
            }
        }
    }

    private func binding(for topic: BuzzKit.Topic) -> Binding<Bool> {
        Binding(
            get: { topics.first(where: { $0.slug == topic.slug })?.isOptedIn ?? topic.isOptedIn },
            set: { enabled in
                Task { await change(topic.slug, to: enabled) }
            }
        )
    }

    private func reload() async {
        isLoading = true
        let generation = writeGeneration
        do {
            let loaded = try await load()
            if generation == writeGeneration {
                topics = loaded
            }
            failed = false
        } catch {
            failed = topics.isEmpty
        }
        isLoading = false
    }

    private func changeChannel(_ slug: String, channel: BuzzKit.Channel, to enabled: Bool) async {
        guard let saveChannel else {
            await change(slug, to: enabled)
            return
        }
        writeGeneration += 1
        let generation = writeGeneration
        do {
            let updated = try await saveChannel(slug, channel, enabled)
            if generation == writeGeneration {
                topics = updated
            }
        } catch {
            if generation == writeGeneration {
                await reload()
            }
        }
    }

    private func change(_ slug: String, to enabled: Bool) async {
        writeGeneration += 1
        let generation = writeGeneration
        topics = topics.map { topic in
            topic.slug == slug ? topic.settingAllChannels(optedIn: enabled) : topic
        }
        do {
            let updated = try await save(slug, enabled)
            if generation == writeGeneration {
                topics = updated
            }
        } catch {
            if generation == writeGeneration {
                await reload()
            }
        }
    }
}

extension BuzzKitPreferencesView where Row == BuzzKitTopicRow {
    /// Creates the screen with the default row: the topic's name, its description, and
    /// a toggle.
    public init() {
        self.init { topic, isOptedIn in
            BuzzKitTopicRow(topic: topic, isOptedIn: isOptedIn)
        }
    }

    /// Creates the default screen over a custom data source.
    public init(
        load: @escaping @Sendable () async throws -> [BuzzKit.Topic],
        save: @escaping @Sendable (String, Bool) async throws -> [BuzzKit.Topic],
        saveChannel: (@Sendable (String, BuzzKit.Channel, Bool) async throws -> [BuzzKit.Topic])? = nil
    ) {
        self.init(load: load, save: save, saveChannel: saveChannel) { topic, isOptedIn in
            BuzzKitTopicRow(topic: topic, isOptedIn: isOptedIn)
        }
    }
}

/// The default row of ``BuzzKitPreferencesView``.
public struct BuzzKitTopicRow: View {
    let topic: BuzzKit.Topic
    let isOptedIn: Binding<Bool>

    public var body: some View {
        Toggle(isOn: isOptedIn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                if let description = topic.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}


/// The default row for a topic offered on more than one channel: the name, a summary
/// of where it is on, and a menu with Off and a toggle per channel.
public struct BuzzKitChannelRow: View {
    let topic: BuzzKit.Topic
    let setChannel: (BuzzKit.Channel, Bool) -> Void
    let setAll: (Bool) -> Void

    private var summary: String {
        let on = topic.channels
            .filter(\.value.isOptedIn)
            .keys
            .map(\.displayName)
            .sorted()
        return on.isEmpty ? "Off" : on.joined(separator: ", ")
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                if let description = topic.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button("Off") { setAll(false) }
                Divider()
                ForEach(topic.channels.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { channel in
                    Button {
                        setChannel(channel, !(topic.channels[channel]?.isOptedIn ?? false))
                    } label: {
                        if topic.channels[channel]?.isOptedIn == true {
                            Label(channel.displayName, systemImage: "checkmark")
                        } else {
                            Text(channel.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(summary)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
