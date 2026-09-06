import Foundation
import Testing
@testable import BuzzKit

@Suite struct MergeResolutionTests {
    @Test func settlesWhenTheIdentifyCallSucceeded() {
        #expect(resolveMerge(after: nil) == .settle)
    }

    @Test func settlesWhenTheApiRefusesTheMergePermanently() {
        let identified = BuzzKitError.api(code: "merge_source_identified", message: "not anonymous")
        let verified = BuzzKitError.api(code: "merge_source_verified", message: "verified")
        #expect(resolveMerge(after: identified) == .settle)
        #expect(resolveMerge(after: verified) == .settle)
    }

    @Test func retainsWhenTheApiAsksForARetry() {
        let pending = BuzzKitError.api(code: "merge_history_pending", message: "retry")
        #expect(resolveMerge(after: pending) == .retain)
    }

    @Test func retainsWhenTheDeviceIsOffline() {
        let offline = BuzzKitError.network(underlying: URLError(.notConnectedToInternet))
        #expect(resolveMerge(after: offline) == .retain)
    }

    @Test func retainsOnAnyOtherApiFailure() {
        #expect(resolveMerge(after: BuzzKitError.api(code: "internal", message: "boom")) == .retain)
        #expect(resolveMerge(after: BuzzKitError.invalidResponse) == .retain)
        #expect(resolveMerge(after: BuzzKitError.notConfigured) == .retain)
    }
}
