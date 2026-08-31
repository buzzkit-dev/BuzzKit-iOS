import Foundation

struct Envelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let data: Value?
    let error: APIProblem?
}

struct APIProblem: Decodable, Sendable {
    let code: String
    let message: String
    let param: String?
}

/// Errors the SDK surfaces from its async APIs.
public enum BuzzKitError: Error, Sendable, LocalizedError {
    /// ``BuzzKit/configure(with:)`` has not run yet.
    case notConfigured
    /// No user is identified and the call requires one.
    case notIdentified
    /// The device declined or restricted notification permission.
    case permissionDenied
    /// The API rejected the request; `code` matches the REST error codes.
    case api(code: String, message: String)
    /// The request never produced a response.
    case network(underlying: Error)
    /// The response could not be decoded.
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "BuzzKit is not configured. Call BuzzKit.configure(apiKey:) first."
        case .notIdentified:
            return "No user is identified. Call BuzzKit.identify(_:) first."
        case .permissionDenied:
            return "Notification permission was declined or restricted."
        case .api(let code, let message):
            return "The API refused the request (\(code)): \(message)"
        case .network(let underlying):
            if (underlying as? URLError)?.code == .timedOut {
                return "Timed out waiting for the device push token. On the simulator this usually means the build is unsigned or the runtime cannot register with APNs."
            }
            return "The request did not reach the API: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "The API answered in an unexpected shape."
        }
    }
}
