import Foundation
import Testing
@testable import BuzzKit

@Suite struct JSONValueTests {
    @Test func roundTripsEveryShape() throws {
        let value: JSONValue = [
            "name": "workout.completed",
            "duration": 42,
            "ratio": 0.5,
            "done": true,
            "note": nil,
            "tags": ["gym", "morning"],
            "nested": ["level": 2],
        ]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func bridgesFromFoundation() throws {
        let any: [String: Any] = ["count": 3, "on": true, "name": "a", "list": [1, 2]]
        let value = try #require(JSONValue(any: any))
        #expect(value == ["count": 3, "on": true, "name": "a", "list": [1, 2]])
    }
}
