import Foundation

enum Spillover {
    static let key = "nse.spillover"
    static let limit = 200

    struct Entry: Codable, Sendable {
        let id: String
        let externalId: String
        let identityHash: String?
        let name: String
        let data: [String: JSONValue]?
        let timestamp: Date

        var queued: QueuedEvent {
            QueuedEvent(
                id: id,
                externalId: externalId,
                identityHash: identityHash,
                name: name,
                data: data,
                timestamp: timestamp
            )
        }
    }

    static func append(_ entry: Entry, to store: KeyValueStore) {
        var entries = load(from: store)
        guard entries.count < limit else { return }
        entries.append(entry)
        save(entries, to: store)
    }

    static func drain(from store: KeyValueStore) -> [Entry] {
        let entries = load(from: store)
        guard !entries.isEmpty else { return [] }
        store.set(nil as String?, for: key)
        return entries
    }

    private static func load(from store: KeyValueStore) -> [Entry] {
        guard let raw = store.string(key),
            let entries = try? JSONCoding.decoder.decode([Entry].self, from: Data(raw.utf8))
        else { return [] }
        return entries
    }

    private static func save(_ entries: [Entry], to store: KeyValueStore) {
        let encoded = (try? JSONCoding.encoder.encode(entries)).map { String(decoding: $0, as: UTF8.self) }
        store.set(encoded, for: key)
    }
}

enum SharedConfigurationKey {
    static let apiKey = "shared.apiKey"
    static let apiURL = "shared.apiURL"
}
