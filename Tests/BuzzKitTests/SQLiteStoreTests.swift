import Foundation
import Testing
@testable import BuzzKit

@Suite struct SQLiteStoreTests {
    @Test func createsInsertsAndQueries() throws {
        let store = try SQLiteStore(path: ":memory:")
        try store.execute("CREATE TABLE events (id TEXT PRIMARY KEY, name TEXT NOT NULL, at REAL NOT NULL)")
        try store.execute(
            "INSERT INTO events (id, name, at) VALUES (?, ?, ?)",
            [.text("evt_1"), .text("workout.completed"), .real(123.5)]
        )
        let rows = try store.query("SELECT id, name, at FROM events")
        #expect(rows.count == 1)
        #expect(rows[0][0] == .text("evt_1"))
        #expect(rows[0][2] == .real(123.5))
    }

    @Test func reportsChangesAndHandlesNull() throws {
        let store = try SQLiteStore(path: ":memory:")
        try store.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, note TEXT)")
        try store.execute("INSERT INTO items (note) VALUES (?)", [.null])
        #expect(store.changes == 1)
        let rows = try store.query("SELECT note FROM items")
        #expect(rows[0][0] == .null)
    }

    @Test func throwsOnBadSQL() throws {
        let store = try SQLiteStore(path: ":memory:")
        #expect(throws: SQLiteError.self) {
            try store.execute("NOT REAL SQL")
        }
    }
}
