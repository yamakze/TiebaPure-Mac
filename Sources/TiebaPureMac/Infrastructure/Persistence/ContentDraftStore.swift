import Foundation
import SwiftData

private struct ContentDraftByteCountUpdate: Sendable {
    let persistentID: PersistentIdentifier
    let byteCount: Int
}

private struct ContentDraftBackgroundLoadResult: Sendable {
    let outcome: ContentDraftLoadOutcome
    let byteCountUpdate: ContentDraftByteCountUpdate?
}


/// External attachment data is faulted only inside this model actor. The main
/// context receives scalar byte-count updates and can enforce capacity without
/// touching every attachment blob.
@ModelActor

private actor ContentDraftDatabaseActor {
    func load(
        accountID: String,
        target: ContentSubmissionTarget
    ) throws -> ContentDraftBackgroundLoadResult {
        try Task.checkCancellation()
        let requestedAccountID = accountID
        let requestedTargetKey = target.draftKey
        let records = try modelContext.fetch(FetchDescriptor<ContentDraftRecord>(
            predicate: #Predicate { record in
                record.accountID == requestedAccountID
                    && record.targetKey == requestedTargetKey
            }
        ))
        guard let record = preferredRecord(in: records) else {
            return ContentDraftBackgroundLoadResult(outcome: .loaded(nil), byteCountUpdate: nil)
        }
        guard let storedTarget = try? JSONDecoder().decode(
            ContentSubmissionTarget.self,
            from: record.targetData
        ), storedTarget.draftKey == requestedTargetKey else {
            return ContentDraftBackgroundLoadResult(
                outcome: .damaged(.targetMetadata),
                byteCountUpdate: nil
            )
        }

        let imagesBlob = record.imagesBlob
        try Task.checkCancellation()
        let byteCountUpdate = record.imagesByteCount == imagesBlob.count
            ? nil
            : ContentDraftByteCountUpdate(
                persistentID: record.persistentModelID,
                byteCount: imagesBlob.count
            )
        let images: [ContentSubmissionImage]
        switch ContentDraftImageBlobCodec.decodeWithIntegrity(imagesBlob) {
        case let .decoded(decodedImages):
            images = decodedImages
        case .damagedContainer:
            return ContentDraftBackgroundLoadResult(
                outcome: .damaged(.attachmentContainer),
                byteCountUpdate: byteCountUpdate
            )
        case .cancelled:
            throw CancellationError()
        }

        return ContentDraftBackgroundLoadResult(
            outcome: .loaded(ContentDraft(
                accountID: accountID,
                target: storedTarget,
                title: record.title,
                body: record.body,
                images: images,
                updatedAt: record.updatedAt
            )),
            byteCountUpdate: byteCountUpdate
        )
    }

    func missingByteCountUpdates() throws -> [ContentDraftByteCountUpdate] {
        let records = try modelContext.fetch(FetchDescriptor<ContentDraftRecord>())
        var updates: [ContentDraftByteCountUpdate] = []
        updates.reserveCapacity(records.count)
        for record in records {
            if let byteCount = record.imagesByteCount, byteCount >= 0 {
                continue
            }
            try Task.checkCancellation()
            updates.append(ContentDraftByteCountUpdate(
                persistentID: record.persistentModelID,
                byteCount: record.imagesBlob.count
            ))
        }
        return updates
    }

    private func preferredRecord(in records: [ContentDraftRecord]) -> ContentDraftRecord? {
        records.max {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.persistentModelID < $1.persistentModelID
        }
    }
}

@MainActor

final class SwiftDataContentDraftPersistenceBackend: ContentDraftPersistenceBackend {

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let databaseActorTask: Task<ContentDraftDatabaseActor, Never>
    private let persistentBackendIsAvailable: Bool
    private(set) var persistenceAvailability: PersistenceAvailability
    private var maintenanceTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        persistenceAvailability: PersistenceAvailability? = nil
    ) {
        self.modelContainer = modelContainer
        modelContext = modelContainer.mainContext
        databaseActorTask = Task.detached(priority: .utility) {
            ContentDraftDatabaseActor(modelContainer: modelContainer)
        }
        let availability = persistenceAvailability ?? .available
        persistentBackendIsAvailable = availability.canPersist
        self.persistenceAvailability = availability
    }

    /// Returns `true` when the store was read successfully. `draft` is `nil`
    /// for a successful miss, keeping that case distinct from a read failure.
    @discardableResult
    func load(
        accountID: String,
        target: ContentSubmissionTarget,
        into draft: inout ContentDraft?
    ) -> Bool {
        draft = nil
        guard requirePersistence(operation: "load content draft") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            let matches = try matchingRecords(
                accountID: normalizedAccountID,
                targetKey: target.draftKey
            )
            guard let record = preferredRecord(in: matches) else {
                markPersistenceSucceeded()
                return true
            }
            guard let storedTarget = try? JSONDecoder().decode(
                ContentSubmissionTarget.self,
                from: record.targetData
            ), storedTarget.draftKey == target.draftKey else {
                throw ContentDraftStoreError.damagedTarget
            }
            let imagesBlob = record.imagesBlob
            let images: [ContentSubmissionImage]
            switch ContentDraftImageBlobCodec.decodeWithIntegrity(imagesBlob) {
            case let .decoded(decodedImages):
                images = decodedImages
            case .damagedContainer:
                throw ContentDraftStoreError.damagedAttachmentContainer
            case .cancelled:
                return false
            }
            record.imagesByteCount = imagesBlob.count
            draft = ContentDraft(
                accountID: normalizedAccountID,
                target: storedTarget,
                title: record.title,
                body: record.body,
                images: images,
                updatedAt: record.updatedAt
            )
            try modelContext.save()
            markPersistenceSucceeded()
            return true
        } catch ContentDraftStoreError.damagedTarget {
            PersistenceDiagnostics.report(
                ContentDraftStoreError.damagedTarget,
                operation: "load content draft"
            )
            markPersistenceSucceeded()
            return false
        } catch ContentDraftStoreError.damagedAttachmentContainer {
            PersistenceDiagnostics.report(
                ContentDraftStoreError.damagedAttachmentContainer,
                operation: "load content draft"
            )
            markPersistenceSucceeded()
            return false
        } catch {
            PersistenceDiagnostics.report(error, operation: "load content draft")
            persistenceAvailability = .unavailable
            return false
        }
    }

    func draft(accountID: String, target: ContentSubmissionTarget) -> ContentDraft? {
        var loaded: ContentDraft?
        guard load(accountID: accountID, target: target, into: &loaded) else { return nil }
        return loaded
    }

    func loadAsync(
        accountID: String,
        target: ContentSubmissionTarget
    ) async -> ContentDraftLoadOutcome {
        guard requirePersistence(operation: "load content draft") else { return .unavailable }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            let databaseActor = await databaseActorTask.value
            try Task.checkCancellation()
            let result = try await databaseActor.load(
                accountID: normalizedAccountID,
                target: target
            )
            guard Task.isCancelled == false else { return .unavailable }
            if let update = result.byteCountUpdate {
                try applyByteCountUpdates([update])
                try modelContext.save()
            }
            markPersistenceSucceeded()
            return result.outcome
        } catch is CancellationError {
            return .unavailable
        } catch {
            modelContext.rollback()
            PersistenceDiagnostics.report(error, operation: "load content draft")
            persistenceAvailability = .unavailable
            return .unavailable
        }
    }

    @discardableResult
    func save(_ draft: ContentDraft) -> Bool {
        guard requirePersistence(operation: "save content draft") else { return false }
        let normalizedID: String
        do {
            normalizedID = try normalizedAccountID(draft.accountID)
        } catch {
            return fail(ContentDraftStoreError.invalidAccountID, operation: "save content draft")
        }

        do {
            let imagesBlob = try ContentDraftImageBlobCodec.encode(draft.images)
            let needsMaintenance = try persist(
                draft,
                normalizedID: normalizedID,
                imagesBlob: imagesBlob
            )
            if needsMaintenance {
                scheduleMaintenance()
            }
            markPersistenceSucceeded()
            return true
        } catch {
            modelContext.rollback()
            return fail(error, operation: "save content draft")
        }
    }

    func saveAsync(_ draft: ContentDraft) async throws {
        guard requirePersistence(operation: "save content draft") else {
            throw ContentDraftStoreError.persistenceUnavailable
        }
        let normalizedID: String
        do {
            normalizedID = try normalizedAccountID(draft.accountID)
        } catch {
            _ = fail(ContentDraftStoreError.invalidAccountID, operation: "save content draft")
            throw ContentDraftStoreError.invalidAccountID
        }

        do {
            let images = draft.images
            let encodingTask = Task.detached(priority: .userInitiated) {
                try ContentDraftImageBlobCodec.encode(images)
            }
            let imagesBlob = try await withTaskCancellationHandler {
                try await encodingTask.value
            } onCancel: {
                encodingTask.cancel()
            }
            try Task.checkCancellation()
            if try hasUnknownByteCounts() {
                let didRepair = await repairLegacyMetadataAndPruneAsync()
                try Task.checkCancellation()
                guard didRepair else {
                    throw ContentDraftStoreError.persistenceUnavailable
                }
            }
            try Task.checkCancellation()
            let needsMaintenance = try persist(
                draft,
                normalizedID: normalizedID,
                imagesBlob: imagesBlob
            )
            if needsMaintenance {
                scheduleMaintenance()
            }
            markPersistenceSucceeded()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            modelContext.rollback()
            _ = fail(error, operation: "save content draft")
            throw error
        }
    }

    @discardableResult
    func save(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage],
        updatedAt: Date = Date()
    ) -> Bool {
        save(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: updatedAt
        ))
    }

    func saveAsync(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage],
        updatedAt: Date = Date()
    ) async throws {
        try await saveAsync(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: updatedAt
        ))
    }

    @discardableResult
    func delete(accountID: String, target: ContentSubmissionTarget) -> Bool {
        guard requirePersistence(operation: "delete content draft") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            for record in try matchingRecords(
                accountID: normalizedAccountID,
                targetKey: target.draftKey
            ) {
                modelContext.delete(record)
            }
            try modelContext.save()
            markPersistenceSucceeded()
            return true
        } catch {
            modelContext.rollback()
            return fail(error, operation: "delete content draft")
        }
    }

    @discardableResult
    func clear(accountID: String) -> Bool {
        guard requirePersistence(operation: "clear content drafts") else { return false }
        do {
            let normalizedAccountID = try normalizedAccountID(accountID)
            let requestedAccountID = normalizedAccountID
            let records = try modelContext.fetch(FetchDescriptor<ContentDraftRecord>(
                predicate: #Predicate { record in
                    record.accountID == requestedAccountID
                }
            ))
            for record in records {
                modelContext.delete(record)
            }
            try modelContext.save()
            markPersistenceSucceeded()
            return true
        } catch {
            modelContext.rollback()
            return fail(error, operation: "clear content drafts")
        }
    }

    private func matchingRecords(accountID: String, targetKey: String) throws -> [ContentDraftRecord] {
        let requestedAccountID = accountID
        let requestedTargetKey = targetKey
        return try modelContext.fetch(FetchDescriptor<ContentDraftRecord>(
            predicate: #Predicate { record in
                record.accountID == requestedAccountID
                    && record.targetKey == requestedTargetKey
            }
        ))
    }

    private func persist(
        _ draft: ContentDraft,
        normalizedID: String,
        imagesBlob: Data
    ) throws -> Bool {
        guard imagesBlob.count <= ContentDraftPolicy.maximumAttachmentBytesPerDraft else {
            throw ContentDraftStoreError.attachmentBudgetExceeded
        }
        let targetData = try JSONEncoder().encode(draft.target)
        let matches = try matchingRecords(
            accountID: normalizedID,
            targetKey: draft.target.draftKey
        )
        if let record = preferredRecord(in: matches) {
            record.targetData = targetData
            record.title = draft.title
            record.body = draft.body
            record.imagesBlob = imagesBlob
            record.imagesByteCount = imagesBlob.count
            record.updatedAt = draft.updatedAt
            for duplicate in matches where duplicate !== record {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(ContentDraftRecord(
                accountID: normalizedID,
                targetKey: draft.target.draftKey,
                targetData: targetData,
                title: draft.title,
                body: draft.body,
                imagesBlob: imagesBlob,
                imagesByteCount: imagesBlob.count,
                updatedAt: draft.updatedAt
            ))
        }
        let needsMaintenance = try pruneUsingByteCountMetadata()
        try modelContext.save()
        return needsMaintenance
    }

    private func normalizedAccountID(_ accountID: String) throws -> String {
        let normalized = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw ContentDraftStoreError.invalidAccountID
        }
        return normalized
    }

    private func preferredRecord(in records: [ContentDraftRecord]) -> ContentDraftRecord? {
        records.max {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.persistentModelID < $1.persistentModelID
        }
    }

    @discardableResult
    func repairLegacyMetadataAndPruneAsync() async -> Bool {
        guard requirePersistence(operation: "repair content draft metadata") else { return false }
        do {
            let databaseActor = await databaseActorTask.value
            guard Task.isCancelled == false else { return false }
            let updates = try await databaseActor.missingByteCountUpdates()
            guard Task.isCancelled == false else { return false }
            try applyByteCountUpdates(updates)
            _ = try pruneUsingByteCountMetadata()
            try modelContext.save()
            markPersistenceSucceeded()
            return true
        } catch is CancellationError {
            return false
        } catch {
            modelContext.rollback()
            return fail(error, operation: "repair content draft metadata")
        }
    }

    private func hasUnknownByteCounts() throws -> Bool {
        try modelContext.fetch(FetchDescriptor<ContentDraftRecord>()).contains { record in
            guard let byteCount = record.imagesByteCount else { return true }
            return byteCount < 0
        }
    }

    private func applyByteCountUpdates(_ updates: [ContentDraftByteCountUpdate]) throws {
        guard updates.isEmpty == false else { return }
        let byteCountsByID = Dictionary(uniqueKeysWithValues: updates.map {
            ($0.persistentID, $0.byteCount)
        })
        for record in try modelContext.fetch(FetchDescriptor<ContentDraftRecord>()) {
            if let byteCount = byteCountsByID[record.persistentModelID] {
                record.imagesByteCount = byteCount
            }
        }
    }

    /// Returns whether legacy records still need an off-main byte-count repair.
    private func pruneUsingByteCountMetadata() throws -> Bool {
        let records = try modelContext.fetch(FetchDescriptor<ContentDraftRecord>())
        let candidates = records.enumerated().map { index, record in
            ContentDraftPruneCandidate(
                sourceIndex: index,
                persistentID: String(describing: record.persistentModelID),
                accountID: record.accountID,
                targetKey: record.targetKey,
                updatedAt: record.updatedAt,
                imagesByteCount: record.imagesByteCount
            )
        }
        let deletionIndices = ContentDraftPruner.deletionIndices(for: candidates)
        for index in deletionIndices {
            modelContext.delete(records[index])
        }
        return records.contains { record in
            guard let byteCount = record.imagesByteCount else { return true }
            return byteCount < 0
        }
    }

    private func scheduleMaintenance() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            _ = await repairLegacyMetadataAndPruneAsync()
            maintenanceTask = nil
        }
    }

    private func requirePersistence(operation: String) -> Bool {
        guard persistentBackendIsAvailable else {
            return fail(ContentDraftStoreError.persistenceUnavailable, operation: operation)
        }
        return true
    }

    private func fail(_ error: Error, operation: String) -> Bool {
        PersistenceDiagnostics.report(error, operation: operation)
        persistenceAvailability = .unavailable
        return false
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }
}

@MainActor
final class ContentDraftStore {
    private let persistence: any ContentDraftPersistenceBackend

    var persistenceAvailability: PersistenceAvailability {
        persistence.persistenceAvailability
    }

    init(persistence: any ContentDraftPersistenceBackend) {
        self.persistence = persistence
    }

    convenience init() {
        self.init(persistence: SwiftDataContentDraftPersistenceBackend(
            modelContainer: AppModelContainer.shared.container,
            persistenceAvailability: AppModelContainer.shared.availability
        ))
    }

    convenience init(
        modelContainer: ModelContainer,
        persistenceAvailability: PersistenceAvailability? = nil
    ) {
        self.init(persistence: SwiftDataContentDraftPersistenceBackend(
            modelContainer: modelContainer,
            persistenceAvailability: persistenceAvailability
        ))
    }

    @discardableResult
    func load(
        accountID: String,
        target: ContentSubmissionTarget,
        into draft: inout ContentDraft?
    ) -> Bool {
        persistence.load(accountID: accountID, target: target, into: &draft)
    }

    func draft(accountID: String, target: ContentSubmissionTarget) -> ContentDraft? {
        persistence.draft(accountID: accountID, target: target)
    }

    func loadAsync(
        accountID: String,
        target: ContentSubmissionTarget
    ) async -> ContentDraftLoadOutcome {
        await persistence.loadAsync(accountID: accountID, target: target)
    }

    @discardableResult
    func save(_ draft: ContentDraft) -> Bool {
        persistence.save(draft)
    }

    func saveAsync(_ draft: ContentDraft) async throws {
        try await persistence.saveAsync(draft)
    }

    @discardableResult
    func save(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage],
        updatedAt: Date = Date()
    ) -> Bool {
        save(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: updatedAt
        ))
    }

    func saveAsync(
        accountID: String,
        target: ContentSubmissionTarget,
        title: String,
        body: String,
        images: [ContentSubmissionImage],
        updatedAt: Date = Date()
    ) async throws {
        try await saveAsync(ContentDraft(
            accountID: accountID,
            target: target,
            title: title,
            body: body,
            images: images,
            updatedAt: updatedAt
        ))
    }

    @discardableResult
    func delete(accountID: String, target: ContentSubmissionTarget) -> Bool {
        persistence.delete(accountID: accountID, target: target)
    }

    @discardableResult
    func clear(accountID: String) -> Bool {
        persistence.clear(accountID: accountID)
    }

    @discardableResult
    func repairLegacyMetadataAndPruneAsync() async -> Bool {
        await persistence.repairLegacyMetadataAndPruneAsync()
    }
}
