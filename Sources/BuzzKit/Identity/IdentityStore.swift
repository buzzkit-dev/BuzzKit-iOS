import Foundation

struct Identity: Sendable, Equatable {
    var externalId: String
    var identityHash: String?
    var isAnonymous: Bool

    var subscriberIdentity: SubscriberIdentity {
        SubscriberIdentity(externalId: externalId, identityHash: identityHash)
    }
}

actor IdentityStore {
    private let store: KeyValueStore
    private var anonymousId: String
    private var externalId: String?
    private var identityHash: String?

    init(store: KeyValueStore) {
        self.store = store
        if let existing = store.string(StorageKey.anonymousId) {
            anonymousId = existing
        } else {
            anonymousId = Self.makeAnonymousId()
            store.set(anonymousId, for: StorageKey.anonymousId)
        }
        externalId = store.string(StorageKey.externalId)
        identityHash = store.string(StorageKey.identityHash)
    }

    var current: Identity {
        Identity(
            externalId: externalId ?? anonymousId,
            identityHash: externalId == nil ? nil : identityHash,
            isAnonymous: externalId == nil
        )
    }

    func identify(externalId newExternalId: String, identityHash newHash: String?) -> (identity: Identity, changed: Bool) {
        let changed = newExternalId != externalId || newHash != identityHash
        externalId = newExternalId
        identityHash = newHash
        store.set(newExternalId, for: StorageKey.externalId)
        store.set(newHash, for: StorageKey.identityHash)
        return (current, changed)
    }

    func logout() -> Identity {
        externalId = nil
        identityHash = nil
        anonymousId = Self.makeAnonymousId()
        store.set(anonymousId, for: StorageKey.anonymousId)
        store.set(nil as String?, for: StorageKey.externalId)
        store.set(nil as String?, for: StorageKey.identityHash)
        return current
    }

    private static func makeAnonymousId() -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var generator = SystemRandomNumberGenerator()
        let suffix = (0..<21).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }
        return "anon_" + String(suffix)
    }
}
