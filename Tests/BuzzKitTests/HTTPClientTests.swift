import Foundation
import Testing
@testable import BuzzKit

@Suite struct HTTPClientTests {
    @Test func decodesEnvelopeData() async throws {
        let mock = MockAPI()
        mock.stub { _ in
            jsonResponse(200, #"{"success":true,"data":{"id":"sub_1","subscriberId":"subr_1","channel":"push","platform":"ios","environment":"production","endpoint":"token","enabled":true,"status":"active","deleted":null}}"#)
        }
        let subscription = try await mock.client().send(
            HTTPRequest(method: .get, path: "v1/client/anything", body: nil, headers: [:]),
            as: SubscriptionDTO.self
        )
        #expect(subscription.id == "sub_1")
        #expect(subscription.enabled)
    }

    @Test func surfacesAPIErrors() async throws {
        let mock = MockAPI()
        mock.stub { _ in
            jsonResponse(401, #"{"success":false,"error":{"code":"invalid_identity","message":"Identity hash is invalid"}}"#)
        }
        await #expect(throws: BuzzKitError.self) {
            _ = try await mock.client().send(
                HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: [:]),
                as: [TopicDTO].self
            )
        }
    }

    @Test func retriesServerErrorsThenSucceeds() async throws {
        let mock = MockAPI()
        let counter = LockedState(0)
        mock.stub { _ in
            let attempt = counter.withLock { value -> Int in
                value += 1
                return value
            }
            if attempt < 3 {
                return jsonResponse(500, #"{"success":false,"error":{"code":"internal","message":"boom"}}"#)
            }
            return jsonResponse(200, #"{"success":true,"data":[]}"#)
        }
        let topics = try await mock.client().send(
            HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: [:]),
            as: [TopicDTO].self
        )
        #expect(topics.isEmpty)
        #expect(counter.read() == 3)
    }

    @Test func sendsAuthAndIdentityHeaders() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(200, #"{"success":true,"data":[]}"#) }
        let identity = SubscriberIdentity(externalId: "user_42", identityHash: "abc123")
        _ = try await mock.client().send(
            HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: identity.headers),
            as: [TopicDTO].self
        )
        let request = try #require(mock.requests().first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(mock.key)")
        #expect(request.value(forHTTPHeaderField: "BuzzKit-Subscriber") == "user_42")
        #expect(request.value(forHTTPHeaderField: "BuzzKit-Identity") == "abc123")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("buzzkit-ios/") == true)
    }

    @Test func exhaustedServerErrorsThrowRetryable() async throws {
        let mock = MockAPI()
        mock.stub { _ in
            jsonResponse(500, #"{"success":false,"error":{"code":"internal","message":"boom"}}"#)
        }
        do {
            _ = try await mock.client(maxAttempts: 2).send(
                HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: [:]),
                as: [TopicDTO].self
            )
            Issue.record("expected a throw")
        } catch let error as BuzzKitError {
            guard case .network = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
        }
    }

    @Test func decodesFractionalAndPlainDates() throws {
        #expect(ISO8601.date(from: "2026-08-29T12:34:56.789Z") != nil)
        #expect(ISO8601.date(from: "2026-08-29T12:34:56Z") != nil)
        #expect(ISO8601.date(from: "not a date") == nil)
    }
}

@Suite struct BuzzKitErrorTests {
    @Test func everyCaseExplainsItself() {
        let cases: [BuzzKitError] = [
            .notConfigured, .notIdentified, .permissionDenied,
            .api(code: "invalid_identity", message: "Bad hash"),
            .network(underlying: URLError(.timedOut)),
            .network(underlying: URLError(.notConnectedToInternet)),
            .invalidResponse,
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(!description.contains("error 1"))
        }
        #expect(BuzzKitError.api(code: "x", message: "y").errorDescription?.contains("x") == true)
        #expect(
            BuzzKitError.network(underlying: URLError(.timedOut)).errorDescription?.contains("token") == true
        )
    }

    @Test func envelopeWithoutDataOrErrorIsInvalid() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(200, #"{"success":true}"#) }
        await #expect(throws: BuzzKitError.self) {
            _ = try await mock.client().send(
                HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: [:]),
                as: [TopicDTO].self
            )
        }
    }
}
