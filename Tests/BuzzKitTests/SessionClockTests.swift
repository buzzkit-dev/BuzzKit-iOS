import Foundation
import Testing
@testable import BuzzKit

@Suite struct SessionClockTests {
    @Test func firstForegroundOpensSession() {
        var clock = SessionClock()
        let events = clock.foregrounded(at: Date(timeIntervalSince1970: 1000))
        #expect(events.map(\.name) == [EventNames.appOpened])
    }

    @Test func quickResumeEmitsNothing() {
        var clock = SessionClock()
        _ = clock.foregrounded(at: Date(timeIntervalSince1970: 1000))
        _ = clock.backgrounded(at: Date(timeIntervalSince1970: 1010))
        let events = clock.foregrounded(at: Date(timeIntervalSince1970: 1020))
        #expect(events.isEmpty)
    }

    @Test func backgroundEmitsBackgrounded() {
        var clock = SessionClock()
        _ = clock.foregrounded(at: Date(timeIntervalSince1970: 1000))
        let events = clock.backgrounded(at: Date(timeIntervalSince1970: 1042))
        #expect(events.map(\.name) == [EventNames.appBackgrounded])
    }

    @Test func longGapEndsSessionAndOpensNew() {
        var clock = SessionClock()
        _ = clock.foregrounded(at: Date(timeIntervalSince1970: 1000))
        _ = clock.backgrounded(at: Date(timeIntervalSince1970: 1090))
        let events = clock.foregrounded(at: Date(timeIntervalSince1970: 2000))
        #expect(events.map(\.name) == [EventNames.sessionEnded, EventNames.appOpened])
        #expect(events[0].data?["durationSec"] == .number(90))
        #expect(events[0].timestamp == Date(timeIntervalSince1970: 1090))
    }

    @Test func backgroundWithoutSessionEmitsNothing() {
        var clock = SessionClock()
        #expect(clock.backgrounded(at: Date()).isEmpty)
    }
}
