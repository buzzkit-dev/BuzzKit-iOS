import Foundation

struct QueuedEvent: Sendable, Equatable {
    let id: String
    let externalId: String
    let identityHash: String?
    let name: String
    let data: [String: JSONValue]?
    let timestamp: Date
}

actor EventQueue {
    static let batchLimit = 100
    static let maxAttempts = 20

    private var store: SQLiteStore?
    private let api: ClientAPI
    private let logger: BKLogger
    private var scheduledFlush: Task<Void, Never>?
    private var flushing = false

    init(store: SQLiteStore?, api: ClientAPI, logger: BKLogger) {
        self.api = api
        self.logger = logger
        self.store = Self.prepare(store, logger: logger)
    }

    private static func prepare(_ store: SQLiteStore?, logger: BKLogger) -> SQLiteStore? {
        guard let store else { return nil }
        do {
            let schema = [
                "CREATE TABLE IF NOT EXISTS event_queue (",
                "id TEXT PRIMARY KEY,",
                "external_id TEXT NOT NULL,",
                "identity_hash TEXT,",
                "name TEXT NOT NULL,",
                "data TEXT,",
                "timestamp REAL NOT NULL,",
                "attempts INTEGER NOT NULL DEFAULT 0)",
            ].joined(separator: " ")
            try store.execute(schema)
            return store
        } catch {
            logger.error("Event queue storage unavailable, events will not be recorded: \(error)")
            return nil
        }
    }

    func enqueue(_ event: QueuedEvent) {
        guard let store else { return }
        let data = event.data.flatMap { payload in
            (try? JSONCoding.encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) }
        }
        do {
            try store.execute(
                "INSERT OR IGNORE INTO event_queue (id, external_id, identity_hash, name, data, timestamp) VALUES (?, ?, ?, ?, ?, ?)",
                [
                    .text(event.id),
                    .text(event.externalId),
                    event.identityHash.map { .text($0) } ?? .null,
                    .text(event.name),
                    data.map { .text($0) } ?? .null,
                    .real(event.timestamp.timeIntervalSince1970),
                ]
            )
        } catch {
            logger.error("Failed to queue event \(event.name): \(error)")
        }
    }

    func scheduleFlush(after seconds: Double = 3) {
        scheduledFlush?.cancel()
        scheduledFlush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }

        while true {
            let batch = nextBatch()
            guard !batch.isEmpty else { return }
            let identity = batch[0]
            do {
                _ = try await api.trackEvents(
                    TrackEventsBody(
                        externalId: identity.externalId,
                        identityHash: identity.identityHash,
                        source: "ios",
                        events: batch.map { event in
                            EventBody(id: event.id, name: event.name, data: event.data, timestamp: event.timestamp)
                        }
                    )
                )
                delete(ids: batch.map(\.id))
                logger.debug("Flushed \(batch.count) events")
            } catch let error as BuzzKitError {
                if case .api(let code, let message) = error {
                    logger.error("Server rejected \(batch.count) events (\(code)): \(message); dropping the batch")
                    delete(ids: batch.map(\.id))
                    continue
                }
                logger.warn("Event flush failed, keeping \(batch.count) events queued: \(error)")
                markFailed(ids: batch.map(\.id))
                return
            } catch {
                logger.warn("Event flush failed, keeping \(batch.count) events queued: \(error)")
                markFailed(ids: batch.map(\.id))
                return
            }
        }
    }

    func pendingCount() -> Int {
        guard let store else { return 0 }
        let rows = (try? store.query("SELECT COUNT(*) FROM event_queue")) ?? []
        return rows.first?.first?.integerValue.map(Int.init) ?? 0
    }

    private func nextBatch() -> [QueuedEvent] {
        guard let store else { return [] }
        do {
            guard let head = try store.query(
                "SELECT external_id, identity_hash FROM event_queue ORDER BY timestamp, id LIMIT 1"
            ).first else { return [] }
            let externalId = head[0].textValue ?? ""
            let identityHash = head[1].textValue
            let rows = try store.query(
                """
                SELECT id, external_id, identity_hash, name, data, timestamp FROM event_queue
                WHERE external_id = ? AND identity_hash IS ?
                ORDER BY timestamp, id LIMIT ?
                """,
                [.text(externalId), identityHash.map { .text($0) } ?? .null, .integer(Int64(Self.batchLimit))]
            )
            return rows.compactMap { row in
                guard let id = row[0].textValue, let name = row[3].textValue,
                    case .real(let epoch) = row[5] else { return nil }
                let data = row[4].textValue.flatMap { text in
                    try? JSONCoding.decoder.decode([String: JSONValue].self, from: Data(text.utf8))
                }
                return QueuedEvent(
                    id: id,
                    externalId: row[1].textValue ?? "",
                    identityHash: row[2].textValue,
                    name: name,
                    data: data,
                    timestamp: Date(timeIntervalSince1970: epoch)
                )
            }
        } catch {
            logger.error("Failed to read the event queue: \(error)")
            return []
        }
    }

    private func delete(ids: [String]) {
        guard let store else { return }
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try? store.execute("DELETE FROM event_queue WHERE id IN (\(marks))", ids.map { .text($0) })
    }

    private func markFailed(ids: [String]) {
        guard let store else { return }
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try? store.execute("UPDATE event_queue SET attempts = attempts + 1 WHERE id IN (\(marks))", ids.map { .text($0) })
        try? store.execute("DELETE FROM event_queue WHERE attempts >= ?", [.integer(Int64(Self.maxAttempts))])
    }
}
