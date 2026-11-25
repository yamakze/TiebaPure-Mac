import SwiftData
import XCTest
@testable import TiebaPureMac

final class SwiftDataOrderedCollectionPersistenceTests: XCTestCase {
    private enum InjectedFailure: Error {
        case beforeCommit
    }

    @MainActor
    func testHistoryAdaptersPreserveOrderAndUnchangedRows() throws {
        let container = try makeInMemoryModelContainer()
        let recent = SwiftDataRecentForumPersistence(modelContainer: container)
        let search = SwiftDataSearchHistoryPersistence(modelContainer: container)

        let recentEntries = [
            makeRecentForum(name: "second", updatedAt: 2),
            makeRecentForum(name: "first", updatedAt: 1)
        ]
        let searchEntries = ["second", "first"]

        try recent.replaceAll(recentEntries)
        try search.replaceAll(searchEntries)

        let reopenedRecent = SwiftDataRecentForumPersistence(modelContainer: container)
        let reopenedSearch = SwiftDataSearchHistoryPersistence(modelContainer: container)

        XCTAssertEqual(try reopenedRecent.load(), recentEntries)
        XCTAssertEqual(try reopenedSearch.load(), searchEntries)

        let previousSearchRows = try container.mainContext.fetch(FetchDescriptor<SearchHistoryRecord>())
        let unchanged = try XCTUnwrap(previousSearchRows.first { $0.keyword == "first" }).persistentModelID
        try search.replaceAll(["first", "new"])
        XCTAssertEqual(try reopenedSearch.load(), ["first", "new"])
        let currentSearchRows = try container.mainContext.fetch(FetchDescriptor<SearchHistoryRecord>())
        let retained = try XCTUnwrap(currentSearchRows.first { $0.keyword == "first" })
        XCTAssertEqual(retained.persistentModelID, unchanged)
        XCTAssertEqual(try reopenedRecent.load(), recentEntries)
    }

    @MainActor
    func testBrowsingAsyncExecutorCommitIsVisibleToFreshLoader() async throws {
        let container = try makeInMemoryModelContainer(models: [BrowsingHistoryRecord.self])
        let writer = SwiftDataBrowsingHistoryPersistence(modelContainer: container)
        let first = makeBrowsingEntry(threadID: 1, visitedAt: 1)
        let second = makeBrowsingEntry(threadID: 2, visitedAt: 2)

        _ = try await writer.upsert(first, limit: 10)
        let committed = try await writer.upsert(second, limit: 10)
        XCTAssertEqual(committed.map(\.threadID), [2, 1])

        let loader = SwiftDataBrowsingHistoryPersistence(modelContainer: container)
        XCTAssertEqual(try loader.load().map(\.threadID), [2, 1])
    }

    @MainActor
    func testBeforeCommitFailureRollsBackHistoryAdapters() throws {
        let container = try makeInMemoryModelContainer()
        let recent = SwiftDataRecentForumPersistence(modelContainer: container)
        let search = SwiftDataSearchHistoryPersistence(modelContainer: container)

        let originalRecent = [makeRecentForum(name: "first", updatedAt: 1)]
        let originalSearch = ["first"]
        try recent.replaceAll(originalRecent)
        try search.replaceAll(originalSearch)

        XCTAssertThrowsError(
            try recent.replaceAll([makeRecentForum(name: "second", updatedAt: 2)]) {
                throw InjectedFailure.beforeCommit
            }
        )
        XCTAssertThrowsError(
            try search.replaceAll(["second"]) {
                throw InjectedFailure.beforeCommit
            }
        )

        XCTAssertEqual(try recent.load(), originalRecent)
        XCTAssertEqual(try search.load(), originalSearch)
    }

    @MainActor
    func testReaderHistoryUsesOnlyItsNamedStoreAndReopensSavedEntries() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let schema = Schema(AppModelContainer.historyModels)
        XCTAssertEqual(Set(schema.entities.map(\.name)), ["RecentForumRecord", "SearchHistoryRecord"])
        let oldURL = base.appendingPathComponent("default.store")
        func openOldStore() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: oldURL))
        }
        do {
            let old = try openOldStore()
            try SwiftDataSearchHistoryPersistence(modelContainer: old).replaceAll(["old"])
        }

        let visits = [makeRecentForum(name: "Swift", updatedAt: 10)]
        do {
            let new = AppModelContainer.openHistory(baseDirectoryURL: base)
            XCTAssertEqual(new.availability, .available)
            let search = SwiftDataSearchHistoryPersistence(modelContainer: new.container)
            let recent = SwiftDataRecentForumPersistence(modelContainer: new.container)
            XCTAssertTrue(try search.load().isEmpty)
            XCTAssertTrue(try recent.load().isEmpty)
            try search.replaceAll(["new"])
            try recent.replaceAll(visits)
        }

        let reopened = AppModelContainer.openHistory(baseDirectoryURL: base)
        XCTAssertEqual(reopened.availability, .available)
        XCTAssertEqual(try SwiftDataSearchHistoryPersistence(modelContainer: reopened.container).load(), ["new"])
        XCTAssertEqual(try SwiftDataRecentForumPersistence(modelContainer: reopened.container).load(), visits)
        let old = try openOldStore()
        XCTAssertEqual(try SwiftDataSearchHistoryPersistence(modelContainer: old).load(), ["old"])
    }

    @MainActor
    func testWritableMemoryFallbackIsClassifiedAsFallbackInsteadOfDurable() throws {
        let container = try makeInMemoryModelContainer()

        XCTAssertEqual(
            SwiftDataBrowsingHistoryPersistence(
                modelContainer: try makeInMemoryModelContainer(models: [BrowsingHistoryRecord.self]),
                persistenceAvailability: .unavailable
            ).capability,
            .fallback
        )
        XCTAssertEqual(
            SwiftDataRecentForumPersistence(
                modelContainer: container,
                persistenceAvailability: .unavailable
            ).capability,
            .fallback
        )
        XCTAssertEqual(
            SwiftDataSearchHistoryPersistence(
                modelContainer: container,
                persistenceAvailability: .unavailable
            ).capability,
            .fallback
        )
    }

    @MainActor
    private func makeInMemoryModelContainer(
        models: [any PersistentModel.Type] = AppModelContainer.historyModels
    ) throws -> ModelContainer {
        let schema = Schema(models)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        )
    }

    private func makeBrowsingEntry(
        threadID: Int64,
        visitedAt: TimeInterval
    ) -> BrowsingHistoryEntry {
        BrowsingHistoryEntry(
            threadID: threadID,
            title: "thread-\(threadID)",
            authorDisplayName: "author-\(threadID)",
            visitedAt: Date(timeIntervalSince1970: visitedAt)
        )
    }

    private func makeRecentForum(
        name: String,
        updatedAt: TimeInterval
    ) -> RecentForum {
        RecentForum(
            name: name,
            displayName: "\(name)吧",
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
