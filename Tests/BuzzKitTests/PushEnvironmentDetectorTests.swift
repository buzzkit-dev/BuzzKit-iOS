import Foundation
import Testing
@testable import BuzzKit

@Suite struct PushEnvironmentDetectorTests {
    @Test func readsDevelopmentEnvironment() {
        let profile = "<key>aps-environment</key>\n\t<string>development</string>"
        #expect(PushEnvironmentDetector.apsEnvironment(in: profile) == "development")
    }

    @Test func readsProductionEnvironment() {
        let profile = "junk before <key>aps-environment</key><string>production</string> junk after"
        #expect(PushEnvironmentDetector.apsEnvironment(in: profile) == "production")
    }

    @Test func missingKeyReturnsNil() {
        #expect(PushEnvironmentDetector.apsEnvironment(in: "<key>get-task-allow</key><true/>") == nil)
    }
}
