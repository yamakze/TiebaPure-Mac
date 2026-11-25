import Foundation
import SwiftData

enum AppModelContainer {
    struct Resolution {
        let container: ModelContainer
        let availability: PersistenceAvailability
    }

    static let historyModels: [any PersistentModel.Type] = [RecentForumRecord.self, SearchHistoryRecord.self]
    static let history = openHistory()
    static let browsingHistory = open("browsing-history.store", models: [BrowsingHistoryRecord.self])
    static let readingPositions = open("reading-positions.store", models: [ThreadReadingPositionRecord.self])
    static let contentDrafts = open("drafts.store", models: [ContentDraftRecord.self])

    static func openHistory(baseDirectoryURL: URL? = nil) -> Resolution {
        open("history.store", models: historyModels, baseDirectoryURL: baseDirectoryURL)
    }

    private static func open(
        _ fileName: String,
        models: [any PersistentModel.Type],
        baseDirectoryURL: URL? = nil
    ) -> Resolution {
        let schema = Schema(models)
        do {
            let directory = try SecurePersistenceLocation.applicationSupport(baseDirectoryURL: baseDirectoryURL).directoryURL
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appendingPathComponent(fileName),
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            return Resolution(container: container, availability: .available)
        } catch {
            PersistenceDiagnostics.report(error, operation: "open \(fileName)")
        }
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            return Resolution(container: container, availability: .unavailable)
        } catch {
            fatalError("In-memory ModelContainer creation failed for \(fileName): \(error)")
        }
    }
}

protocol OrderedPersistentRecord: PersistentModel {
    var sortIndex: Int { get set }
}

@MainActor
enum PersistedRecordStore {
    static func fetchOrdered<Record: OrderedPersistentRecord>(
        _ type: Record.Type,
        in context: ModelContext
    ) throws -> [Record] {
        let records = try context.fetch(FetchDescriptor<Record>())
        return records.sorted { $0.sortIndex < $1.sortIndex }
    }

    static func replaceAll<Record: OrderedPersistentRecord>(
        _ type: Record.Type,
        with records: [Record],
        in context: ModelContext,
        beforeSave: () throws -> Void = {}
    ) throws {
        do {
            let existing = try context.fetch(FetchDescriptor<Record>())
            for record in existing {
                context.delete(record)
            }
            for record in records {
                context.insert(record)
            }
            try beforeSave()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Reorders retained entries in place and writes only additions and removals.
    static func synchronize<Record: OrderedPersistentRecord, Entry: Hashable>(
        _ entries: [Entry],
        in context: ModelContext,
        entry: KeyPath<Record, Entry>,
        makeRecord: (Entry, Int) -> Record,
        beforeSave: () throws -> Void
    ) throws {
        do {
            var existing = Dictionary(grouping: try context.fetch(FetchDescriptor<Record>())) {
                $0[keyPath: entry]
            }
            for (index, value) in entries.enumerated() {
                if let record = existing[value]?.popLast() {
                    if record.sortIndex != index { record.sortIndex = index }
                } else {
                    context.insert(makeRecord(value, index))
                }
            }
            for records in existing.values {
                records.forEach(context.delete)
            }
            try beforeSave()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Updates one reading-position row in place and prunes only duplicates or
    /// rows beyond the retention limit. Scrolling no longer deletes and
    /// reinserts the entire 500-row table for every visible-floor change.
    static func upsertReadingPosition(
        _ position: ThreadReadingPosition,
        limit: Int,
        in context: ModelContext
    ) throws {
        let effectiveLimit = min(
            max(limit, 0),
            LocalThreadLibraryPolicy.maximumReadingPositions
        )
        var records = try context.fetch(FetchDescriptor<ThreadReadingPositionRecord>())
        guard effectiveLimit > 0 else {
            for record in records {
                context.delete(record)
            }
            try save(context)
            return
        }

        if let existing = records.first(where: { $0.threadID == position.threadID }) {
            existing.postIDBitPattern = Int64(bitPattern: position.postID)
            existing.floor = position.floor
            existing.updatedAt = position.updatedAt
        } else {
            let inserted = ThreadReadingPositionRecord(entry: position, sortIndex: 0)
            context.insert(inserted)
            records.append(inserted)
        }

        records.sort {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.threadID < $1.threadID
        }

        var seenThreadIDs = Set<Int64>()
        var retainedCount = 0
        for record in records {
            guard seenThreadIDs.insert(record.threadID).inserted,
                  retainedCount < effectiveLimit else {
                context.delete(record)
                continue
            }
            record.sortIndex = retainedCount
            retainedCount += 1
        }
        try save(context)
    }

    static func deleteReadingPosition(
        threadID: Int64,
        in context: ModelContext
    ) throws {
        let requestedThreadID = threadID
        let records = try context.fetch(FetchDescriptor<ThreadReadingPositionRecord>(
            predicate: #Predicate { record in
                record.threadID == requestedThreadID
            }
        ))
        for record in records {
            context.delete(record)
        }
        try save(context)
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

@Model
final class ThreadReadingPositionRecord {
    var threadID: Int64
    // UInt64 bit pattern; the backing store has no unsigned 64-bit column.
    var postIDBitPattern: Int64
    var floor: Int
    var updatedAt: Date
    var sortIndex: Int

    init(entry: ThreadReadingPosition, sortIndex: Int) {
        self.threadID = entry.threadID
        self.postIDBitPattern = Int64(bitPattern: entry.postID)
        self.floor = entry.floor
        self.updatedAt = entry.updatedAt
        self.sortIndex = sortIndex
    }

    var entry: ThreadReadingPosition {
        ThreadReadingPosition(
            threadID: threadID,
            postID: UInt64(bitPattern: postIDBitPattern),
            floor: floor,
            updatedAt: updatedAt
        )
    }
}

extension ThreadReadingPositionRecord: OrderedPersistentRecord {}

@Model
final class BrowsingHistoryRecord {
    var threadID: Int64
    var forumID: Int64?
    var title: String
    var authorDisplayName: String
    var forumDisplayName: String?
    var visitedAt: Date
    var sortIndex: Int

    init(entry: BrowsingHistoryEntry, sortIndex: Int) {
        self.threadID = entry.threadID
        self.forumID = entry.forumID
        self.title = entry.title
        self.authorDisplayName = entry.authorDisplayName
        self.forumDisplayName = entry.forumDisplayName
        self.visitedAt = entry.visitedAt
        self.sortIndex = sortIndex
    }

    var entry: BrowsingHistoryEntry {
        BrowsingHistoryEntry(
            threadID: threadID,
            forumID: forumID,
            title: title,
            authorDisplayName: authorDisplayName,
            forumDisplayName: forumDisplayName,
            visitedAt: visitedAt
        )
    }
}

extension BrowsingHistoryRecord: OrderedPersistentRecord {}

@Model
final class RecentForumRecord {
    var name: String
    var displayName: String
    var avatarURL: URL?
    var updatedAt: Date
    var sortIndex: Int

    init(entry: RecentForum, sortIndex: Int) {
        self.name = entry.name
        self.displayName = entry.displayName
        self.avatarURL = entry.avatarURL
        self.updatedAt = entry.updatedAt
        self.sortIndex = sortIndex
    }

    var entry: RecentForum {
        RecentForum(
            name: name,
            displayName: displayName,
            avatarURL: avatarURL,
            updatedAt: updatedAt
        )
    }
}

extension RecentForumRecord: OrderedPersistentRecord {}

@Model
final class SearchHistoryRecord {
    var keyword: String
    var sortIndex: Int

    init(keyword: String, sortIndex: Int) {
        self.keyword = keyword
        self.sortIndex = sortIndex
    }
}

extension SearchHistoryRecord: OrderedPersistentRecord {}

@Model
final class ContentDraftRecord {
    var accountID: String
    var targetKey: String
    var targetData: Data
    var title: String
    var body: String
    @Attribute(.externalStorage) var imagesBlob: Data
    var imagesByteCount: Int
    var updatedAt: Date

    init(
        accountID: String,
        targetKey: String,
        targetData: Data,
        title: String,
        body: String,
        imagesBlob: Data,
        updatedAt: Date
    ) {
        self.accountID = accountID
        self.targetKey = targetKey
        self.targetData = targetData
        self.title = title
        self.body = body
        self.imagesBlob = imagesBlob
        self.imagesByteCount = imagesBlob.count
        self.updatedAt = updatedAt
    }
}
