import BuzzKit
import BuzzKitUI
import SwiftUI

enum DemoVariant: String, CaseIterable, Identifiable {
    case grouped
    case sheet
    case tinted
    case plain
    case customRows = "custom-rows"
    case customScreen = "custom-screen"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped: return "Default"
        case .sheet: return "In a sheet"
        case .tinted: return "Brand tinted"
        case .plain: return "Plain list"
        case .customRows: return "Custom rows"
        case .customScreen: return "Fully custom screen"
        }
    }

    var caption: String {
        switch self {
        case .grouped: return "The drop-in view, untouched."
        case .sheet: return "Presented with detents over your own screen."
        case .tinted: return "One .tint modifier rebrands every control."
        case .plain: return "A .listStyle swap, nothing else."
        case .customRows: return "Your rows, our loading and saving."
        case .customScreen: return "Built from the data layer alone."
        }
    }
}

struct GalleryView: View {
    @State private var showsSheet = false

    var body: some View {
        List(DemoVariant.allCases) { variant in
            if variant == .sheet {
                Button {
                    showsSheet = true
                } label: {
                    label(variant)
                }
                .foregroundStyle(.primary)
            } else {
                NavigationLink {
                    DemoVariantView(variant: variant)
                } label: {
                    label(variant)
                }
            }
        }
        .navigationTitle("Preferences demos")
        .sheet(isPresented: $showsSheet) {
            NavigationStack {
                demoPreferences
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsSheet = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func label(_ variant: DemoVariant) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(variant.title)
            Text(variant.caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct DemoVariantView: View {
    let variant: DemoVariant

    var body: some View {
        switch variant {
        case .grouped:
            demoPreferences.navigationTitle("Notifications")
        case .sheet:
            SheetDemo()
        case .tinted:
            demoPreferences
                .tint(.orange)
                .navigationTitle("Notifications")
        case .plain:
            demoPreferences
                .listStyle(.plain)
                .navigationTitle("Notifications")
        case .customRows:
            CustomRowsDemo()
        case .customScreen:
            CustomScreenDemo()
        }
    }
}

var demoPreferences: BuzzKitPreferencesView<BuzzKitTopicRow> {
    BuzzKitPreferencesView(
        load: { DemoPreferences.shared.all() },
        save: { slug, enabled in DemoPreferences.shared.set(slug, enabled: enabled) },
        saveChannel: { slug, channel, enabled in
            DemoPreferences.shared.set(slug, channel: channel, enabled: enabled)
        }
    )
}

struct SheetDemo: View {
    @State private var showsSettings = false

    var body: some View {
        List {
            Section {
                Label("Account", systemImage: "person.crop.circle")
                Label("Payment methods", systemImage: "creditcard")
                Button {
                    showsSettings = true
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }
            } header: {
                Text("Settings")
            }
        }
        .navigationTitle("Profile")
        .task { showsSettings = true }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                demoPreferences
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct CustomRowsDemo: View {
    private func symbol(for slug: String) -> String {
        switch slug {
        case "gym-reminders": return "figure.run"
        case "digest": return "chart.bar.doc.horizontal"
        case "deals": return "tag"
        default: return "sparkles"
        }
    }

    private func color(for slug: String) -> Color {
        switch slug {
        case "gym-reminders": return .indigo
        case "digest": return .teal
        case "deals": return .pink
        default: return .orange
        }
    }

    var body: some View {
        BuzzKitPreferencesView(
            load: { DemoPreferences.shared.all() },
            save: { slug, enabled in DemoPreferences.shared.set(slug, enabled: enabled) }
        ) { topic, isOptedIn in
            HStack(spacing: 12) {
                Image(systemName: symbol(for: topic.slug))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color(for: topic.slug).gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.name)
                        .fontWeight(.medium)
                    if let description = topic.description {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: isOptedIn)
                    .labelsHidden()
            }
            .padding(.vertical, 2)
        }
        .tint(.indigo)
        .navigationTitle("Notifications")
    }
}

struct CustomScreenDemo: View {
    @State private var topics: [BuzzKit.Topic] = DemoPreferences.shared.all()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose what reaches you. Changes apply on every device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(BuzzKit.TopicGroup.group(topics)) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        if let category = group.category {
                            Text(category.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .kerning(0.8)
                        }
                        ForEach(group.topics) { topic in
                            topicCard(topic)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Notifications")
    }

    private func topicCard(_ topic: BuzzKit.Topic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                    .fontWeight(.semibold)
                if let description = topic.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(topic.channels.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { channel in
                    let on = topic.channels[channel]?.isOptedIn == true
                    Button {
                        topics = DemoPreferences.shared.set(topic.slug, channel: channel, enabled: !on)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                            Text(channel.displayName)
                                .font(.footnote.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(on ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
