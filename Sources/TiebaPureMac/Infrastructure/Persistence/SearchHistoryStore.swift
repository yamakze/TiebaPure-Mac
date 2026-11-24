import Combine
import Foundation

@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let persistence: any SearchHistoryPersistence
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    @Published private(set) var items: [String]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.searchHistory",
        limit: Int = SearchHistoryPolicy.maximumStoredEntries,
        persistence: any SearchHistoryPersistence,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        let configuredLimit = min(max(limit, 0), SearchHistoryPolicy.maximumStoredEntries)
        self.defaults = defaults
        self.key = key
        self.limit = configuredLimit
        self.persistence = persistence
        self.faultInjector = faultInjector
        persistentBackendIsAvailable = persistence.capability.acceptsUserMutations
        let snapshot = HistoryStorage.initialSnapshot(
            capability: persistence.capability,
            collection: "search history",
            defaults: defaults,
            legacyKey: key,
            legacyValue: defaults.object(forKey: key),
            decodeLegacy: { _ in defaults.stringArray(forKey: key) },
            load: persistence.load,
            replaceAll: persistence.replaceAll,
            sanitize: { SearchHistoryPolicy.sanitized($0, limit: configuredLimit) },
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
                sanitize: { SearchHistoryPolicy.sanitized($0, limit: limit) },
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair search history")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload search history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func record(_ keyword: String) -> Bool {
        persist(SearchHistoryPolicy.adding(keyword, to: items, limit: limit))
    }

    @discardableResult
    func remove(_ keyword: String) -> Bool {
        persist(SearchHistoryPolicy.removing(keyword, from: items))
    }

    @discardableResult
    func clear() -> Bool {
        let succeeded = persist([])
        if succeeded, persistence.capability.isDurable {
            defaults.removeObject(forKey: key)
        }
        return succeeded
    }

    @discardableResult
    private func persist(_ updated: [String]) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try persistence.replaceAll(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save search history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }
}
