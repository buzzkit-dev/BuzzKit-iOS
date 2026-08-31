import Foundation
import SQLite3

enum SQLiteValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)
    case null

    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var integerValue: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}

struct SQLiteError: Error, Sendable {
    let message: String
}

final class SQLiteStore {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open"
            sqlite3_close_v2(handle)
            throw SQLiteError(message: message)
        }
        self.handle = handle
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA busy_timeout = 3000")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        _ = try run(sql, bindings)
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        try run(sql, bindings)
    }

    var changes: Int {
        Int(sqlite3_changes(handle))
    }

    private func run(_ sql: String, _ bindings: [SQLiteValue]) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .integer(let integer):
                sqlite3_bind_int64(statement, position, integer)
            case .real(let real):
                sqlite3_bind_double(statement, position, real)
            case .blob(let data):
                _ = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(data.count), Self.transient)
                }
            case .null:
                sqlite3_bind_null(statement, position)
            }
        }

        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw SQLiteError(message: String(cString: sqlite3_errmsg(handle)))
            }
            let columns = sqlite3_column_count(statement)
            var row: [SQLiteValue] = []
            row.reserveCapacity(Int(columns))
            for column in 0..<columns {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_TEXT:
                    row.append(.text(String(cString: sqlite3_column_text(statement, column))))
                case SQLITE_INTEGER:
                    row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT:
                    row.append(.real(sqlite3_column_double(statement, column)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    let bytes = sqlite3_column_blob(statement, column)
                    row.append(.blob(bytes.map { Data(bytes: $0, count: count) } ?? Data()))
                default:
                    row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
