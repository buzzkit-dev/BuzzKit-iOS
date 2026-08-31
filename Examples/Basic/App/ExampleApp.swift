import BuzzKit
import SwiftUI

@main
struct ExampleApp: App {
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("apiURL") private var apiURL = "http://localhost:8790"

    init() {
        let key = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let url = UserDefaults.standard.string(forKey: "apiURL") ?? "http://localhost:8790"
        if !key.isEmpty, let parsed = URL(string: url) {
            BuzzKit.configure(with: BuzzKit.Configuration(apiKey: key, apiURL: parsed, logLevel: .debug))
            BuzzKit.actions.register("show_offer") { action in
                print("[Example] show_offer action:", action.data)
            }
            BuzzKit.onDeepLink { url in
                print("[Example] deep link:", url)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
