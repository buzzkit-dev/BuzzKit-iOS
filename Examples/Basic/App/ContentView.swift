import BuzzKit
import BuzzKitUI
import SwiftUI
import UserNotifications

struct ContentView: View {
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("apiURL") private var apiURL = "http://localhost:8790"
    @State private var externalId = "user_42"
    @State private var configured = BuzzKit.isConfigured
    @State private var identifiedAs: String?
    @State private var attributesSent = false
    @State private var permission = ""
    @State private var pushRegistered = false
    @State private var pendingEvents = 0
    @State private var tracked = 0
    @State private var busy: Set<String> = []
    @State private var errorMessage: String?
    @State private var showsSheetDemo = false

    private var previewVariant: DemoVariant? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-preview-preferences") else { return nil }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        return DemoVariant(rawValue: value)
    }

    private var isPreviewing: Bool {
        ProcessInfo.processInfo.arguments.contains("-preview-preferences")
    }

    var body: some View {
        if let variant = previewVariant {
            NavigationStack { DemoVariantView(variant: variant) }
        } else if isPreviewing {
            NavigationStack { GalleryView() }
        } else {
            main
        }
    }

    private var main: some View {
        NavigationStack {
            List {
                connection
                if configured {
                    identity
                    push
                    events
                }
                demos
            }
            .navigationTitle("BuzzKit")
            .task { await refresh() }
            .alert("Something went wrong", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showsSheetDemo) { sheetDemo }
    }

    private var connection: some View {
        Section {
            if configured {
                LabeledContent("API") {
                    Text(URL(string: apiURL)?.host().map { "\($0)" } ?? apiURL)
                }
                LabeledContent("Client key") {
                    Text("\(apiKey.prefix(12))…")
                        .font(.callout.monospaced())
                }
            } else {
                TextField("Client key (bk_pk_…)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("API URL", text: $apiURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Connect") {
                    connect()
                }
                .disabled(apiKey.isEmpty)
            }
        } header: {
            Text("Connection")
        } footer: {
            if !configured {
                Text("Create a client key in the dashboard and paste it here. The URL points at your local API. The interface demos below work without a key.")
            }
        }
    }

    private var identity: some View {
        Section {
            if let identifiedAs {
                LabeledContent("Signed in as", value: identifiedAs)
            } else {
                TextField("External id", text: $externalId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if identifiedAs == nil {
                actionRow("identify", title: "Identify") {
                    BuzzKit.identify(externalId, attributes: ["plan": "trial", "source": "example-app"])
                    try? await Task.sleep(for: .milliseconds(500))
                    identifiedAs = externalId
                }
            } else {
                actionRow("attributes", title: attributesSent ? "Attributes sent" : "Set attributes", done: attributesSent) {
                    BuzzKit.setAttributes(["plan": "pro", "streak": 4])
                    try? await Task.sleep(for: .milliseconds(500))
                    attributesSent = true
                }
                Button("Sign out", role: .destructive) {
                    BuzzKit.logout()
                    identifiedAs = nil
                    attributesSent = false
                }
            }
        } header: {
            Text("Identity")
        } footer: {
            Text(identifiedAs == nil
                ? "Anonymous until you identify. Events still track and carry over."
                : "The subscriber is in your dashboard, with plan and source attributes.")
        }
    }

    private var push: some View {
        Section {
            if pushRegistered {
                LabeledContent("Device", value: "Registered")
            } else {
                actionRow("push", title: "Register for push") {
                    do {
                        _ = try await BuzzKit.registerForPush()
                        pushRegistered = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    await refresh()
                }
            }
            if !permission.isEmpty {
                LabeledContent("Permission", value: permission)
            }
        } header: {
            Text("Push")
        } footer: {
            Text("On the simulator, drag a file from push-samples onto the app to receive a push.")
        }
    }

    private var events: some View {
        Section {
            actionRow("track1", title: "Track workout.completed") {
                BuzzKit.track("workout.completed", data: ["duration": 42])
                tracked += 1
                try? await Task.sleep(for: .milliseconds(300))
                await refresh()
            }
            actionRow("track2", title: "Track checkout.started") {
                BuzzKit.track("checkout.started", data: ["cart": 129.90])
                tracked += 1
                try? await Task.sleep(for: .milliseconds(300))
                await refresh()
            }
            actionRow("flush", title: "Flush queue") {
                await BuzzKit.flushEvents()
                await refresh()
            }
            LabeledContent("Queued on device", value: "\(pendingEvents)")
        } header: {
            Text("Events")
        } footer: {
            Text("Events hit disk before the network, so tracking works offline. Flushed events appear in the dashboard's stream.")
        }
    }

    private var demos: some View {
        Section {
            if configured {
                NavigationLink("Notification settings") {
                    BuzzKitPreferencesView()
                        .navigationTitle("Notifications")
                }
            }
            ForEach(DemoVariant.allCases) { variant in
                if variant == .sheet {
                    Button {
                        showsSheetDemo = true
                    } label: {
                        NavigationLink(variant.title) { EmptyView() }
                    }
                    .foregroundStyle(.primary)
                } else {
                    NavigationLink(variant.title) {
                        DemoVariantView(variant: variant)
                    }
                }
            }
        } header: {
            Text("Preferences interface")
        } footer: {
            Text("Six presentations of the settings screen, from drop-in to fully custom, on demo topics.")
        }
    }

    private func actionRow(
        _ id: String,
        title: String,
        done: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            guard !busy.contains(id) else { return }
            busy.insert(id)
            Task {
                await action()
                busy.remove(id)
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if busy.contains(id) {
                    ProgressView()
                } else if done {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(done)
    }

    private var sheetDemo: some View {
        NavigationStack {
            demoPreferences
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showsSheetDemo = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func connect() {
        guard let url = URL(string: apiURL) else {
            errorMessage = "The API URL is not a valid URL."
            return
        }
        BuzzKit.configure(with: BuzzKit.Configuration(apiKey: apiKey, apiURL: url, logLevel: .debug))
        configured = true
        Task { await refresh() }
    }

    private func refresh() async {
        pendingEvents = await BuzzKit.pendingEventCount()
        let status = await BuzzKit.notificationPermission()
        permission = describe(status)
    }

    private func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporary"
        default: return "Not asked yet"
        }
    }
}
