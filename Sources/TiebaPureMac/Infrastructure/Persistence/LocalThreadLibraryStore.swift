import Combine
import Foundation
import SwiftData

private enum ThreadReadingPositionDatabaseMutation: Sendable {
    case upsert(ThreadReadingPosition, limit: Int)
    case delete(threadID: Int64)
    case deleteAll
}

@ModelActor
private actor ThreadReadingPositionDatabaseActor {
    func apply(
        _ mutation: ThreadReadingPositionDatabaseMutation
    ) throws -> [ThreadReadingPosition] {
        switch mutation {
        case let .upsert(position, limit):
            return try upsert(position, limit: limit)
        case let .delete(threadID):
            return try delete(threadID: threadID)
        case .deleteAll:
            return try deleteAll()
        }
    }

    private func upsert(
        _ position: ThreadReadingPosition,
        limit: Int
    ) throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        let effectiveLimit = min(
            max(limit, 0),
            LocalThreadLibraryPolicy.maximumReadingPositions
        )

        do {
            var records = try modelContext.fetch(
                FetchDescriptor<ThreadReadingPositionRecord>()
            )
            guard effectiveLimit > 0 else {
                for record in records {
                    modelContext.delete(record)
                }
                try Task.checkCancellation()
                try save()
                return []
            }

            if let existing = records.first(where: { $0.threadID == position.threadID }) {
                existing.postIDBitPattern = Int64(bitPattern: position.postID)
                existing.floor = position.floor
                existing.updatedAt = position.updatedAt
            } else {
                let inserted = ThreadReadingPositionRecord(entry: position, sortIndex: 0)
                modelContext.insert(inserted)
                records.append(inserted)
            }

            records.sort {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.threadID < $1.threadID
            }

            var seenThreadIDs = Set<Int64>()
            var retained: [ThreadReadingPositionRecord] = []
            retained.reserveCapacity(min(records.count, effectiveLimit))
            for record in records {
                guard seenThreadIDs.insert(record.threadID).inserted,
                      retained.count < effectiveLimit else {
                    modelContext.delete(record)
                    continue
                }
                record.sortIndex = retained.count
                retained.append(record)
            }
            try Task.checkCancellation()
            try save()
            return retained.map(\.entry)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func delete(threadID: Int64) throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        let requestedThreadID = threadID
        do {
            let records = try modelContext.fetch(FetchDescriptor<ThreadReadingPositionRecord>(
                predicate: #Predicate { record in
                    record.threadID == requestedThreadID
                }
            ))
            for record in records {
                modelContext.delete(record)
            }
            try Task.checkCancellation()
            try save()
            return try orderedPositions()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteAll() throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        do {
            let records = try modelContext.fetch(
                FetchDescriptor<ThreadReadingPositionRecord>()
            )
            for record in records {
                modelContext.delete(record)
            }
            try Task.checkCancellation()
            try save()
            return []
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func orderedPositions() throws -> [ThreadReadingPosition] {
        try modelContext.fetch(FetchDescriptor<ThreadReadingPositionRecord>())
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.entry)
    }

    private func save() throws {
        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }
}

@MainActor
protocol ThreadReadingPositionPersistence: AnyObject {
    var capability: PersistenceCapability { get }

    func load() throws -> [ThreadReadingPosition]
    func replaceAll(
        _ positions: [ThreadReadingPosition],
        beforeCommit: () throws -> Void
    ) throws
    func upsert(_ position: ThreadReadingPosition, limit: Int) throws
    func remove(threadID: Int64) throws
    func removeAll(beforeCommit: () throws -> Void) throws

    func upsertInBackground(
        _ position: ThreadReadingPosition,
        limit: Int
    ) async throws -> [ThreadReadingPosition]
    func removeInBackground(threadID: Int64) async throws -> [ThreadReadingPosition]
    func removeAllInBackground() async throws -> [ThreadReadingPosition]
}

extension ThreadReadingPositionPersistence {
    func replaceAll(_ positions: [ThreadReadingPosition]) throws {
        try replaceAll(positions, beforeCommit: {})
    }

    func removeAll() throws {
        try removeAll(beforeCommit: {})
    }

    func upsertInBackground(
        _ position: ThreadReadingPosition,
        limit: Int
    ) async throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        try upsert(position, limit: limit)
        return try load()
    }

    func removeInBackground(threadID: Int64) async throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        try remove(threadID: threadID)
        return try load()
    }

    func removeAllInBackground() async throws -> [ThreadReadingPosition] {
        try Task.checkCancellation()
        try removeAll()
        return []
    }
}

@MainActor
final class SwiftDataThreadReadingPositionPersistence:
    ThreadReadingPositionPersistence {
    let capability: PersistenceCapability

    private let modelContext: ModelContext
    private let databaseActorTask: Task<ThreadReadingPositionDatabaseActor, Never>

    init(
        modelContainer: ModelContainer,
        persistenceAvailability: PersistenceAvailability? = nil
    ) {
        modelContext = modelContainer.mainContext
        capability = persistenceAvailability?.canPersist == false ? .fallback : .durable
        databaseActorTask = Task.detached(priority: .utility) {
            ThreadReadingPositionDatabaseActor(modelContainer: modelContainer)
        }
    }

    func load() throws -> [ThreadReadingPosition] {
        try PersistedRecordStore.fetchOrdered(
            ThreadReadingPositionRecord.self,
            in: modelContext
        ).map(\.entry)
    }

    func replaceAll(
        _ positions: [ThreadReadingPosition],
        beforeCommit: () throws -> Void
    ) throws {
        try PersistedRecordStore.replaceAll(
            ThreadReadingPositionRecord.self,
            with: positions.enumerated().map {
                ThreadReadingPositionRecord(entry: $0.element, sortIndex: $0.offset)
            },
            in: modelContext,
            beforeSave: beforeCommit
        )
    }

    func upsert(_ position: ThreadReadingPosition, limit: Int) throws {
        try PersistedRecordStore.upsertReadingPosition(
            position,
            limit: limit,
            in: modelContext
        )
    }

    func remove(threadID: Int64) throws {
        try PersistedRecordStore.deleteReadingPosition(
            threadID: threadID,
            in: modelContext
        )
    }

    func removeAll(beforeCommit: () throws -> Void) throws {
        try replaceAll([], beforeCommit: beforeCommit)
    }

    func upsertInBackground(
        _ position: ThreadReadingPosition,
        limit: Int
    ) async throws -> [ThreadReadingPosition] {
        let databaseActor = await databaseActorTask.value
        return try await databaseActor.apply(.upsert(position, limit: limit))
    }

    func removeInBackground(threadID: Int64) async throws -> [ThreadReadingPosition] {
        let databaseActor = await databaseActorTask.value
        return try await databaseActor.apply(.delete(threadID: threadID))
    }

    func removeAllInBackground() async throws -> [ThreadReadingPosition] {
        let databaseActor = await databaseActorTask.value
        return try await databaseActor.apply(.deleteAll)
    }

}

@MainActor
final class LocalThreadLibraryStore: ObservableObject {
    static let shared = LocalThreadLibraryStore(persistence: SwiftDataThreadReadingPositionPersistence(
        modelContainer: AppModelContainer.readingPositions.container,
        persistenceAvailability: AppModelContainer.readingPositions.availability
    ))

    private let readingPositionLimit: Int
    private let now: () -> Date
    private let persistence: any ThreadReadingPositionPersistence
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    private var readingPositionMutationTail: Task<Bool, Never>?
    private var readingPositionMutationTailID: UUID?
    private var pendingReadingPositionMutationCount = 0

    @Published private(set) var readingPositions: [ThreadReadingPosition] = []
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        readingPositionLimit: Int = LocalThreadLibraryPolicy.maximumReadingPositions,
        persistence: any ThreadReadingPositionPersistence,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.readingPositionLimit = min(
            max(readingPositionLimit, 0),
            LocalThreadLibraryPolicy.maximumReadingPositions
        )
        self.now = now
        self.persistence = persistence
        self.faultInjector = faultInjector
        persistentBackendIsAvailable = persistence.capability.acceptsUserMutations
        persistenceAvailability = persistence.capability.availability
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        guard persistence.capability.canAccessBackend else {
            persistenceAvailability = .unavailable
            return false
        }
        guard pendingReadingPositionMutationCount == 0 else { return false }
        var succeeded = true
        do {
            let result = try HistoryStorage.repair(
                try persistence.load(),
                canRepair: persistentBackendIsAvailable,
                replaceAll: persistence.replaceAll,
                sanitize: { LocalThreadLibraryPolicy.sanitizedReadingPositions($0, limit: readingPositionLimit) },
                faultInjector: faultInjector
            )
            readingPositions = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair reading positions")
                succeeded = false
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload reading positions")
            succeeded = false
        }
        if succeeded {
            markPersistenceSucceeded()
        } else {
            persistenceAvailability = .unavailable
        }
        return succeeded
    }

    func position(for threadID: Int64) -> ThreadReadingPosition? {
        readingPositions.first { $0.threadID == threadID }
    }

    @discardableResult
    func recordReadingPositionInBackground(
        threadID: Int64,
        postID: UInt64,
        floor: Int
    ) async -> Bool {
        await enqueueReadingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor
        ).value
    }

    func enqueueReadingPosition(
        threadID: Int64,
        postID: UInt64,
        floor: Int
    ) -> Task<Bool, Never> {
        guard let position = LocalThreadLibraryPolicy.readingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: now()
        ) else { return completedReadingPositionMutation(false) }
        if pendingReadingPositionMutationCount == 0,
           let current = self.position(for: threadID),
           current.postID == postID,
           current.floor == floor {
            return completedReadingPositionMutation(true)
        }
        return enqueueReadingPositionMutation(
            .upsert(position, limit: readingPositionLimit),
            operation: "save reading position"
        )
    }

    @discardableResult
    func clearReadingPositionInBackground(threadID: Int64) async -> Bool {
        await enqueueClearReadingPosition(threadID: threadID).value
    }

    func enqueueClearReadingPosition(threadID: Int64) -> Task<Bool, Never> {
        guard pendingReadingPositionMutationCount > 0
                || readingPositions.contains(where: { $0.threadID == threadID }) else {
            return completedReadingPositionMutation(true)
        }
        return enqueueReadingPositionMutation(
            .delete(threadID: threadID),
            operation: "clear reading position"
        )
    }

    @discardableResult
    func clearReadingPositionsInBackground() async -> Bool {
        await enqueueClearReadingPositions().value
    }

    func enqueueClearReadingPositions() -> Task<Bool, Never> {
        enqueueReadingPositionMutation(
            .deleteAll,
            operation: "clear reading positions"
        )
    }

    func waitForPendingReadingPositionMutations() async {
        while let tail = readingPositionMutationTail {
            _ = await tail.value
        }
    }

    @discardableResult
    func recordReadingPosition(threadID: Int64, postID: UInt64, floor: Int) -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard let position = LocalThreadLibraryPolicy.readingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: now()
        ) else { return false }
        if let current = self.position(for: threadID),
           current.postID == postID,
           current.floor == floor {
            return true
        }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        let updated = LocalThreadLibraryPolicy.addingReadingPosition(
            position,
            to: readingPositions,
            limit: readingPositionLimit
        )
        do {
            try persistence.upsert(position, limit: readingPositionLimit)
            readingPositions = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save reading position")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearReadingPosition(threadID: Int64) -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard readingPositions.contains(where: { $0.threadID == threadID }) else { return true }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try persistence.remove(threadID: threadID)
            readingPositions.removeAll { $0.threadID == threadID }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear reading position")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func clearReadingPositions() -> Bool {
        guard pendingReadingPositionMutationCount == 0 else { return false }
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try persistence.removeAll()
            readingPositions = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear reading positions")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func enqueueReadingPositionMutation(
        _ mutation: ThreadReadingPositionDatabaseMutation,
        operation: String
    ) -> Task<Bool, Never> {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return completedReadingPositionMutation(false)
        }

        let previousMutation = readingPositionMutationTail
        let mutationID = UUID()
        pendingReadingPositionMutationCount += 1
        readingPositionMutationTailID = mutationID

        let mutationTask = Task { @MainActor [weak self] in
            if let previousMutation {
                _ = await previousMutation.value
            }
            guard let self else { return false }
            defer {
                self.pendingReadingPositionMutationCount = max(
                    self.pendingReadingPositionMutationCount - 1,
                    0
                )
                if self.readingPositionMutationTailID == mutationID {
                    self.readingPositionMutationTail = nil
                    self.readingPositionMutationTailID = nil
                }
            }

            do {
                let persisted: [ThreadReadingPosition]
                switch mutation {
                case let .upsert(position, limit):
                    persisted = try await self.persistence.upsertInBackground(
                        position,
                        limit: limit
                    )
                case let .delete(threadID):
                    persisted = try await self.persistence.removeInBackground(
                        threadID: threadID
                    )
                case .deleteAll:
                    persisted = try await self.persistence.removeAllInBackground()
                }
                self.readingPositions = persisted
                self.markPersistenceSucceeded()
                return true
            } catch {
                PersistenceDiagnostics.report(error, operation: operation)
                self.persistenceAvailability = .unavailable
                return false
            }
        }
        readingPositionMutationTail = mutationTask
        return mutationTask
    }

    private func completedReadingPositionMutation(_ result: Bool) -> Task<Bool, Never> {
        Task { result }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }
}
