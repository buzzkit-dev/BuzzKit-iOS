import Foundation

struct ClientAPI: Sendable {
    let http: HTTPClient

    func identify(_ body: IdentifyBody) async throws -> SubscriberDTO {
        try await http.send(request(.post, "v1/client/identify", body: body), as: SubscriberDTO.self)
    }

    func registerSubscription(_ body: RegisterSubscriptionBody) async throws -> SubscriptionDTO {
        try await http.send(request(.post, "v1/client/subscriptions", body: body), as: SubscriptionDTO.self)
    }

    func setSubscriptionEnabled(
        id: String,
        enabled: Bool,
        identity: SubscriberIdentity
    ) async throws -> SubscriptionDTO {
        try await http.send(
            request(.patch, "v1/client/subscriptions/\(id)", body: EnabledBody(enabled: enabled), headers: identity.headers),
            as: SubscriptionDTO.self
        )
    }

    func deleteSubscription(id: String, identity: SubscriberIdentity) async throws {
        _ = try await http.send(
            request(.delete, "v1/client/subscriptions/\(id)", headers: identity.headers),
            as: SubscriptionDTO.self
        )
    }

    func trackEvents(_ body: TrackEventsBody) async throws -> [TrackedEventDTO] {
        try await http.sendList(request(.post, "v1/client/events", body: body), of: TrackedEventDTO.self)
    }

    func registerLiveActivity(_ body: RegisterLiveActivityBody) async throws -> LiveActivityDTO {
        try await http.send(request(.post, "v1/client/live-activities", body: body), as: LiveActivityDTO.self)
    }

    func endLiveActivity(id: String, identity: SubscriberIdentity) async throws {
        _ = try await http.send(
            request(.delete, "v1/client/live-activities/\(id)", headers: identity.headers),
            as: LiveActivityDTO.self
        )
    }

    func preferences(identity: SubscriberIdentity) async throws -> [TopicDTO] {
        try await http.sendList(
            request(.get, "v1/client/preferences", headers: identity.headers),
            of: TopicDTO.self
        )
    }

    func updatePreferences(
        _ changes: [String: PreferenceChange],
        identity: SubscriberIdentity
    ) async throws -> [TopicDTO] {
        try await http.sendList(
            request(.patch, "v1/client/preferences", body: PreferencesBody(preferences: changes), headers: identity.headers),
            of: TopicDTO.self
        )
    }

    private func request(
        _ method: HTTPRequest.Method,
        _ path: String,
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(method: method, path: path, body: nil, headers: headers)
    }

    private func request<Body: Encodable>(
        _ method: HTTPRequest.Method,
        _ path: String,
        body: Body,
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(method: method, path: path, body: try? JSONCoding.encoder.encode(body), headers: headers)
    }
}

struct SubscriberIdentity: Sendable {
    let externalId: String
    let identityHash: String?

    var headers: [String: String] {
        var headers = ["BuzzKit-Subscriber": externalId]
        if let identityHash {
            headers["BuzzKit-Identity"] = identityHash
        }
        return headers
    }
}

struct IdentifyBody: Encodable, Sendable {
    let externalId: String
    let email: String?
    let identityHash: String?
    let attributes: [String: JSONValue]?
    var subscribe: [String: Bool]?
    var pushPermission: String?
    var device: DeviceContext?
}

struct RegisterSubscriptionBody: Encodable, Sendable {
    let externalId: String
    let channel: String
    let platform: String
    let token: String
    let environment: String?
    let identityHash: String?
    var pushPermission: String?
    var device: DeviceContext?
}

struct EnabledBody: Encodable, Sendable {
    let enabled: Bool
}

struct TrackEventsBody: Encodable, Sendable {
    let externalId: String
    let identityHash: String?
    let source: String
    let events: [EventBody]
}

struct EventBody: Encodable, Sendable {
    let id: String
    let name: String
    let data: [String: JSONValue]?
    let timestamp: Date
}

struct PreferencesBody: Encodable, Sendable {
    let preferences: [String: PreferenceChange]
}

enum PreferenceChange: Encodable, Sendable {
    case all(Bool)
    case channels([String: Bool])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all(let enabled): try container.encode(enabled)
        case .channels(let channels): try container.encode(channels)
        }
    }
}

struct RegisterLiveActivityBody: Encodable, Sendable {
    let externalId: String
    let identityHash: String?
    let kind: String
    let activityId: String?
    let attributesType: String
    let token: String
    let environment: String?
}

struct LiveActivityDTO: Decodable, Sendable {
    let id: String
    let activityId: String?
    let attributesType: String
    let kind: String
}

struct SubscriberDTO: Decodable, Sendable {
    let id: String
    let externalId: String
    let attributes: [String: JSONValue]
    let verified: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct SubscriptionDTO: Decodable, Sendable {
    let id: String
    let subscriberId: String
    let channel: String
    let platform: String?
    let environment: String?
    let endpoint: String
    let enabled: Bool
    let status: String
    let deleted: Bool?
}

struct TrackedEventDTO: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct TopicDTO: Decodable, Sendable {
    let slug: String
    let name: String
    let description: String?
    let category: String?
    let channels: [String: ChannelPreferenceDTO]
}

struct ChannelPreferenceDTO: Decodable, Sendable {
    let optedIn: Bool
    let isDefault: Bool
}
