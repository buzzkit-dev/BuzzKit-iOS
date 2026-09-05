import ActivityKit
import Foundation

/// The one Live Activity the harness knows how to run. Shared by the app, which starts
/// and observes it, and the widget extension, which renders it.
struct E2EAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var step: Int
    }

    var name: String
}
