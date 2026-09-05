import Foundation

/// Ships everything the harness observes to the test runner on the host, so assertions
/// are made on what the device actually saw rather than on what the UI happens to show.
enum Reporter {
    nonisolated(unsafe) static var collector: URL?
    nonisolated(unsafe) static var run: String = "unknown"

    static func send(_ kind: String, _ payload: [String: Any] = [:]) {
        guard let collector else { return }

        let body: [String: Any] = [
            "run": run,
            "kind": kind,
            "at": ISO8601DateFormatter().string(from: Date()),
            "payload": payload,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: collector.appendingPathComponent("report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }
}
