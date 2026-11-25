import Observation
import Foundation

@MainActor
@Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore(persistence: AppOrderedCollectionPersistence.searchHistory)

    private let limit: Int
    private let persistence: any SearchHistoryPersistence
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private(set) var items: [String] = []
    private(set) var persistenceAvailability: PersistenceAvailability = .unavailable

    init(
        limit: Int = SearchHistoryPolicy.maximumStoredEntries,
        persistence: any SearchHistoryPersistence,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        self.limit = min(max(limit, 0), SearchHistoryPolicy.maximumStoredEntries)
        self.persistence = persistence
        self.faultInjector = faultInjector
        persistentBackendIsAvailable = persistence.capability.acceptsUserMutations
        reload()
    }

    /// Returns whether the snapshot was read, including from a non-durable backend.
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
        let updated = SearchHistoryPolicy.adding(keyword, to: items, limit: limit)
        if updated == items && persistenceAvailability.canPersist { return true }
        return persist(updated)
    }

    @discardableResult
    func remove(_ keyword: String) -> Bool {
        persist(SearchHistoryPolicy.removing(keyword, from: items))
    }

    @discardableResult
    func clear() -> Bool {
        persist([])
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
