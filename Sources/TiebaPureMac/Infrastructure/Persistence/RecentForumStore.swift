import Combine
import Foundation

@MainActor
final class RecentForumStore: ObservableObject {
    static let shared = RecentForumStore()

    private let key: String
    private let limit: Int
    private let defaults: UserDefaults
    private let now: () -> Date
    private let persistence: any RecentForumPersistence
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    @Published private(set) var items: [RecentForum]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.recentForums",
        limit: Int = RecentForumPolicy.maximumStoredEntries,
        persistence: any RecentForumPersistence,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        let configuredLimit = min(max(limit, 0), RecentForumPolicy.maximumStoredEntries)
        self.limit = configuredLimit
        self.now = now
        self.persistence = persistence
        self.faultInjector = faultInjector
        persistentBackendIsAvailable = persistence.capability.acceptsUserMutations
        let snapshot = HistoryStorage.initialSnapshot(
            capability: persistence.capability,
            collection: "recent forums",
            defaults: defaults,
            legacyKey: key,
            legacyValue: defaults.data(forKey: key),
            decodeLegacy: { PersistedArrayDecoder.decode(RecentForum.self, from: $0) },
            load: persistence.load,
            replaceAll: persistence.replaceAll,
            sanitize: { RecentForumPolicy.sanitized($0, limit: configuredLimit) },
            faultInjector: faultInjector
        )
        items = snapshot.items
        persistenceAvailability = snapshot.availability
    }

    @discardableResult
    func reload() -> Bool {
        guard persistence.capability.canAccessBackend else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            let result = HistoryStorage.repair(
                try persistence.load(),
                canRepair: persistentBackendIsAvailable,
                replaceAll: persistence.replaceAll,
                sanitize: { RecentForumPolicy.sanitized($0, limit: limit) },
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair recent forums")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload recent forums")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func save(_ forum: Forum) -> Bool {
        let recent = RecentForum(
            name: forum.name,
            displayName: forum.displayName,
            avatarURL: forum.avatarURL,
            updatedAt: now()
        )
        return save(recent)
    }

    @discardableResult
    func save(name: String, displayName: String? = nil, avatarURL: URL? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        return save(RecentForum(
            name: trimmed,
            displayName: displayName ?? "\(trimmed)吧",
            avatarURL: avatarURL,
            updatedAt: now()
        ))
    }

    @discardableResult
    func clear() -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try persistence.replaceAll([])
            if persistence.capability.isDurable {
                defaults.removeObject(forKey: key)
            }
            items = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear recent forums")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func save(_ recent: RecentForum) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        return persist(
            RecentForumPolicy.sanitized([recent] + items, limit: limit),
            operation: "save recent forums"
        )
    }

    /// Removes individual entries. The identifier is the case-insensitive forum
    /// name, matching `RecentForum.id`, so a row removed in the list matches
    /// the stored record even when the two differ in case.
    @discardableResult
    func remove(ids: Set<String>) -> Bool {
        guard ids.isEmpty == false else { return true }
        let normalizedIDs = Set(ids.map { $0.lowercased() })
        let updated = items.filter { normalizedIDs.contains($0.id) == false }
        guard updated.count != items.count else { return true }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        guard updated.isEmpty == false else { return clear() }
        return persist(updated, operation: "remove recent forums")
    }

    private func persist(_ updated: [RecentForum], operation: String) -> Bool {
        do {
            try persistence.replaceAll(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: operation)
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }
}
