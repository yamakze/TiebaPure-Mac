import Combine
import Foundation

private enum BrowsingHistoryMutation: Sendable {
    case upsert(BrowsingHistoryEntry, limit: Int)
    case delete(threadIDs: Set<Int64>)
    case deleteAll
}

@MainActor
final class BrowsingHistoryStore: ObservableObject {
    static let shared = BrowsingHistoryStore()

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let now: () -> Date
    private let persistence: any BrowsingHistoryPersistence
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private var mutationTail: Task<Bool, Never>?
    private var mutationTailID: UUID?
    private var pendingMutationCount = 0
    @Published private(set) var items: [BrowsingHistoryEntry]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.browsingHistory",
        limit: Int = BrowsingHistoryPolicy.maximumStoredEntries,
        persistence: any BrowsingHistoryPersistence,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = min(max(limit, 0), BrowsingHistoryPolicy.maximumStoredEntries)
        self.now = now
        self.persistence = persistence
        self.faultInjector = faultInjector
        let initialAvailability = persistence.capability.availability
        persistentBackendIsAvailable = persistence.capability.acceptsUserMutations
        self.persistenceAvailability = initialAvailability
        var legacyFallback: [BrowsingHistoryEntry]?
        var migrationFailed = false
        do {
            try Self.migrateLegacyStorage(
                defaults: defaults,
                key: key,
                persistence: persistence,
                limit: self.limit,
                legacyFallback: &legacyFallback,
                faultInjector: faultInjector
            )
        } catch {
            PersistenceDiagnostics.report(error, operation: "migrate browsing history")
            self.persistenceAvailability = .unavailable
            migrationFailed = true
        }
        if persistence.capability.canAccessBackend {
            do {
                let result = try Self.loadAndRepairItems(
                    persistence: persistence,
                    limit: self.limit,
                    canRepair: persistentBackendIsAvailable,
                    faultInjector: faultInjector
                )
                items = result.value
                if let error = result.repairError {
                    PersistenceDiagnostics.report(error, operation: "repair browsing history")
                    self.persistenceAvailability = .unavailable
                }
            } catch {
                PersistenceDiagnostics.report(error, operation: "load browsing history")
                items = migrationFailed ? (legacyFallback ?? []) : []
                self.persistenceAvailability = .unavailable
            }
        } else {
            items = legacyFallback ?? []
        }
        if migrationFailed, items.isEmpty, let legacyFallback {
            items = legacyFallback
        }
    }

    @discardableResult
    func reload() -> Bool {
        guard persistence.capability.canAccessBackend else {
            persistenceAvailability = .unavailable
            return false
        }
        // The background actor owns the persistent context while a mutation is
        // queued. Do not let a synchronous main-context repair race that save.
        guard pendingMutationCount == 0 else { return false }
        do {
            let result = try Self.loadAndRepairItems(
                persistence: persistence,
                limit: limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair browsing history")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func record(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) -> Bool {
        guard pendingMutationCount == 0,
              let entry = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: now()
        ) else { return false }
        return persist(BrowsingHistoryPolicy.adding(entry, to: items, limit: limit))
    }

    @discardableResult
    func recordInBackground(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) async -> Bool {
        await enqueueRecord(
            thread: thread,
            forum: forum,
            fallbackForumID: fallbackForumID
        ).value
    }

    func enqueueRecord(
        thread: ThreadSummary,
        forum: Forum? = nil,
        fallbackForumID: Int64? = nil
    ) -> Task<Bool, Never> {
        guard let entry = BrowsingHistoryPolicy.entry(
            for: thread,
            forum: forum,
            fallbackForumID: fallbackForumID,
            visitedAt: now()
        ) else {
            return completedMutation(false)
        }
        return enqueueMutation(
            .upsert(entry, limit: limit),
            operation: "save browsing history"
        )
    }

    @discardableResult
    func remove(threadIDs: Set<Int64>) -> Bool {
        guard pendingMutationCount == 0 else { return false }
        guard threadIDs.isEmpty == false else { return true }
        return persist(BrowsingHistoryPolicy.removing(threadIDs: threadIDs, from: items))
    }

    @discardableResult
    func removeInBackground(threadIDs: Set<Int64>) async -> Bool {
        guard threadIDs.isEmpty == false else { return true }
        return await enqueueMutation(
            .delete(threadIDs: threadIDs),
            operation: "delete browsing history"
        ).value
    }

    @discardableResult
    func clear() -> Bool {
        guard pendingMutationCount == 0 else { return false }
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
            PersistenceDiagnostics.report(error, operation: "clear browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearInBackground() async -> Bool {
        await enqueueMutation(
            .deleteAll,
            operation: "clear browsing history",
            removesLegacyValueOnSuccess: true
        ).value
    }

    func waitForPendingMutations() async {
        while let tail = mutationTail {
            _ = await tail.value
        }
    }

    @discardableResult
    private func persist(_ updated: [BrowsingHistoryEntry]) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        guard updated.isEmpty == false else {
            return clear()
        }
        do {
            try persistence.replaceAll(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save browsing history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func enqueueMutation(
        _ mutation: BrowsingHistoryMutation,
        operation: String,
        removesLegacyValueOnSuccess: Bool = false
    ) -> Task<Bool, Never> {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return completedMutation(false)
        }

        let previousMutation = mutationTail
        let mutationID = UUID()
        pendingMutationCount += 1
        mutationTailID = mutationID

        let task = Task { @MainActor [weak self] in
            if let previousMutation {
                _ = await previousMutation.value
            }
            guard let self else { return false }
            defer {
                self.pendingMutationCount = max(self.pendingMutationCount - 1, 0)
                if self.mutationTailID == mutationID {
                    self.mutationTail = nil
                    self.mutationTailID = nil
                }
            }

            do {
                switch mutation {
                case let .upsert(entry, limit):
                    self.items = try await self.persistence.upsert(entry, limit: limit)
                case let .delete(threadIDs):
                    self.items = try await self.persistence.remove(threadIDs: threadIDs)
                case .deleteAll:
                    self.items = try await self.persistence.removeAll()
                }
                if removesLegacyValueOnSuccess, self.persistence.capability.isDurable {
                    self.defaults.removeObject(forKey: self.key)
                }
                self.markPersistenceSucceeded()
                return true
            } catch is CancellationError {
                return false
            } catch {
                PersistenceDiagnostics.report(error, operation: operation)
                self.persistenceAvailability = .unavailable
                return false
            }
        }
        mutationTail = task
        return task
    }

    private func completedMutation(_ result: Bool) -> Task<Bool, Never> {
        Task { result }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }

    private static func loadAndRepairItems(
        persistence: any BrowsingHistoryPersistence,
        limit: Int,
        canRepair: Bool,
        faultInjector: PersistenceFaultInjector = .none
    ) throws -> PersistenceLoadResult<[BrowsingHistoryEntry]> {
        let raw = try persistence.load()
        let sanitized = BrowsingHistoryPolicy.sanitized(
            raw,
            limit: limit
        )
        if canRepair, raw != sanitized {
            do {
                try persistence.replaceAll(sanitized) {
                    try faultInjector.check(.repair)
                }
            } catch {
                return PersistenceLoadResult(value: sanitized, repairError: error)
            }
        }
        return PersistenceLoadResult(value: sanitized, repairError: nil)
    }

    // One-time import of the pre-SwiftData UserDefaults JSON blob.
    private static func migrateLegacyStorage(
        defaults: UserDefaults,
        key: String,
        persistence: any BrowsingHistoryPersistence,
        limit: Int,
        legacyFallback: inout [BrowsingHistoryEntry]?,
        faultInjector: PersistenceFaultInjector
    ) throws {
        guard let data = defaults.data(forKey: key) else { return }
        let decodedLegacy = {
            PersistedArrayDecoder.decode(BrowsingHistoryEntry.self, from: data)
                .map { BrowsingHistoryPolicy.sanitized($0, limit: limit) }
        }
        guard persistence.capability.canAccessBackend else {
            legacyFallback = decodedLegacy()
            return
        }
        let existing: [BrowsingHistoryEntry]
        do {
            existing = try persistence.load()
        } catch {
            legacyFallback = decodedLegacy()
            throw error
        }
        let source: [BrowsingHistoryEntry]
        if existing.isEmpty {
            guard let decoded = decodedLegacy() else {
                throw LegacyStorageMigration.DecodeError.invalidTopLevelArray
            }
            source = decoded
            legacyFallback = source
        } else {
            source = existing
        }
        let sanitized = BrowsingHistoryPolicy.sanitized(source, limit: limit)
        try LegacyStorageMigration.persistThenRemoveLegacyValue(
            defaults: defaults,
            key: key,
            destinationIsDurable: persistence.capability.isDurable
        ) {
            try persistence.replaceAll(sanitized) {
                try faultInjector.check(.legacyMigration)
            }
        }
    }
}
