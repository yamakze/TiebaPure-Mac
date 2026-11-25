import SwiftData
import XCTest
@testable import TiebaPureMac

final class ContentDraftTests: XCTestCase {
    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([ContentDraftRecord.self])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func makeFramedBlob(version: UInt8, payloads: [Data]) -> Data {
        var blob = Data([0x54, 0x50, 0x44, 0x49, version, 0, 0, 0])
        for payload in payloads {
            appendBigEndian(UInt32(payload.count), to: &blob)
            appendBigEndian(checksum(payload), to: &blob)
            blob.append(payload)
        }
        return blob
    }

    private func makeLegacyImageBlob(_ images: [ContentSubmissionImage]) throws -> Data {
        try makeFramedBlob(
            version: 1,
            payloads: images.map { try JSONEncoder().encode($0) }
        )
    }

    private func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func checksum(_ data: Data) -> UInt32 {
        data.reduce(2_166_136_261) { value, byte in
            (value ^ UInt32(byte)) &* 16_777_619
        }
    }

    private func makeTarget(
        kind: ContentSubmissionKind = .threadReply,
        threadID: Int64 = 100,
        parentPostID: UInt64? = nil
    ) -> ContentSubmissionTarget {
        ContentSubmissionTarget(
            kind: kind,
            forumID: 10,
            forumName: "fixture",
            forumDisplayName: "测试吧",
            threadID: kind == .newThread ? nil : threadID,
            threadTitle: kind == .newThread ? nil : "测试帖子",
            parentPostID: parentPostID,
            parentFloor: parentPostID == nil ? nil : 2,
            subpostID: nil,
            replyUserID: nil,
            replyUserDisplayName: nil
        )
    }

    private func makeImage(_ marker: UInt8) -> ContentSubmissionImage {
        ContentSubmissionImage(
            id: UUID(),
            data: Data([marker, marker &+ 1, marker &+ 2]),
            pixelWidth: 20,
            pixelHeight: 30,
            mimeType: "image/jpeg"
        )
    }

    @MainActor
    func testDraftsAreIsolatedByAccountAndTarget() throws {
        let store = ContentDraftStore(modelContainer: try makeInMemoryModelContainer())
        let firstTarget = makeTarget(threadID: 100)
        let secondTarget = makeTarget(threadID: 200)

        XCTAssertTrue(store.save(
            accountID: "account-a",
            target: firstTarget,
            title: "A1",
            body: "first",
            images: [],
            updatedAt: Date(timeIntervalSince1970: 10)
        ))
        XCTAssertTrue(store.save(
            accountID: "account-a",
            target: secondTarget,
            title: "A2",
            body: "second",
            images: [],
            updatedAt: Date(timeIntervalSince1970: 20)
        ))
        XCTAssertTrue(store.save(
            accountID: "account-b",
            target: firstTarget,
            title: "B1",
            body: "third",
            images: [],
            updatedAt: Date(timeIntervalSince1970: 30)
        ))

        XCTAssertEqual(store.draft(accountID: "account-a", target: firstTarget)?.body, "first")
        XCTAssertEqual(store.draft(accountID: "account-a", target: secondTarget)?.body, "second")
        XCTAssertEqual(store.draft(accountID: "account-b", target: firstTarget)?.body, "third")
        XCTAssertNil(store.draft(accountID: "account-b", target: secondTarget))
    }

    @MainActor
    func testImagesRoundTrip() throws {
        let store = ContentDraftStore(modelContainer: try makeInMemoryModelContainer())
        let target = makeTarget()
        let images = [makeImage(1), makeImage(10)]

        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "title",
            body: "body",
            images: images,
            updatedAt: Date(timeIntervalSince1970: 123)
        ))

        let loaded = try XCTUnwrap(store.draft(accountID: "account", target: target))
        XCTAssertEqual(loaded.title, "title")
        XCTAssertEqual(loaded.body, "body")
        XCTAssertEqual(loaded.images, images)
        XCTAssertEqual(loaded.updatedAt, Date(timeIntervalSince1970: 123))
    }

    @MainActor
    func testAsyncDraftPathRoundTripsAttachments() async throws {
        let store = ContentDraftStore(modelContainer: try makeInMemoryModelContainer())
        let target = makeTarget()
        let image = makeImage(42)

        try await store.saveAsync(
            accountID: "account",
            target: target,
            title: "title",
            body: "body",
            images: [image]
        )

        let outcome = await store.loadAsync(accountID: "account", target: target)
        guard case let .loaded(draft) = outcome else {
            return XCTFail("Expected the asynchronous draft load to succeed")
        }
        XCTAssertEqual(draft?.images, [image])
    }

    @MainActor
    func testCancelledAsyncSaveDoesNotWriteOrReportPersistenceFailure() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()

        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.saveAsync(
                accountID: "account",
                target: target,
                title: "title",
                body: "body",
                images: [makeImage(1)]
            )
        }

        do {
            try await task.value
            XCTFail("A cancelled save must preserve cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(store.persistenceAvailability, .available)
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).isEmpty
        )
    }

    @MainActor
    func testLoadingLegacyDraftDoesNotPruneTheDraftBeingOpened() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let imagesBlob = try ContentDraftImageBlobCodec.encode([])
        let oldestTarget = makeTarget(threadID: 1)

        for index in 0...ContentDraftPolicy.maximumDraftsGlobally {
            let target = makeTarget(threadID: Int64(index + 1))
            container.mainContext.insert(ContentDraftRecord(
                accountID: "account-\(index % 3)",
                targetKey: target.draftKey,
                targetData: try JSONEncoder().encode(target),
                title: "title-\(index)",
                body: "body-\(index)",
                imagesBlob: imagesBlob,
                imagesByteCount: nil,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        try container.mainContext.save()

        let outcome = await store.loadAsync(accountID: "account-0", target: oldestTarget)
        guard case let .loaded(draft) = outcome else {
            return XCTFail("Expected the legacy draft to load")
        }
        XCTAssertEqual(draft?.body, "body-0")
        let records = try container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>())
        XCTAssertEqual(records.count, ContentDraftPolicy.maximumDraftsGlobally + 1)
        XCTAssertTrue(records.contains { $0.targetKey == oldestTarget.draftKey })
    }

    @MainActor
    func testDeleteAndClearOnlyRemoveRequestedDrafts() throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let firstTarget = makeTarget(threadID: 1)
        let secondTarget = makeTarget(threadID: 2)
        XCTAssertTrue(store.save(accountID: "a", target: firstTarget, title: "", body: "1", images: []))
        XCTAssertTrue(store.save(accountID: "a", target: secondTarget, title: "", body: "2", images: []))
        XCTAssertTrue(store.save(accountID: "b", target: firstTarget, title: "", body: "3", images: []))

        XCTAssertTrue(store.delete(accountID: "a", target: firstTarget))
        XCTAssertNil(store.draft(accountID: "a", target: firstTarget))
        XCTAssertNotNil(store.draft(accountID: "a", target: secondTarget))
        XCTAssertNotNil(store.draft(accountID: "b", target: firstTarget))

        XCTAssertTrue(store.clear(accountID: "a"))
        XCTAssertNil(store.draft(accountID: "a", target: secondTarget))
        XCTAssertNotNil(store.draft(accountID: "b", target: firstTarget))
    }

    @MainActor
    func testCapacityEvictsOldestDraftPerAccount() throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        for index in 0...ContentDraftPolicy.maximumDraftsPerAccount {
            XCTAssertTrue(store.save(
                accountID: "limited",
                target: makeTarget(threadID: Int64(index + 1)),
                title: "",
                body: "\(index)",
                images: [],
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        XCTAssertTrue(store.save(
            accountID: "other",
            target: makeTarget(threadID: 999),
            title: "",
            body: "other",
            images: [],
            updatedAt: .distantPast
        ))

        let records = try container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>())
        XCTAssertEqual(records.filter { $0.accountID == "limited" }.count, 100)
        XCTAssertNil(store.draft(accountID: "limited", target: makeTarget(threadID: 1)))
        XCTAssertNotNil(store.draft(accountID: "limited", target: makeTarget(threadID: 101)))
        XCTAssertNotNil(store.draft(accountID: "other", target: makeTarget(threadID: 999)))
    }

    @MainActor
    func testAnyDamagedAttachmentFrameBlocksDraftUntilDeletion() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()
        let first = makeImage(1)
        let second = makeImage(9)
        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "kept title",
            body: "kept body",
            images: [first, second]
        ))

        let record = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        var damaged = record.imagesBlob
        XCTAssertGreaterThan(damaged.count, 16)
        damaged[16] ^= 0xff
        record.imagesBlob = damaged
        try container.mainContext.save()

        let outcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(outcome, .damaged(.attachmentContainer))
        XCTAssertTrue(store.delete(accountID: "account", target: target))
        let deletedOutcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(deletedOutcome, .loaded(nil))
    }

    @MainActor
    func testChecksummedButUndecodableAttachmentFrameBlocksDraft() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()
        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "kept title",
            body: "kept body",
            images: [makeImage(1)]
        ))

        let record = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        record.imagesBlob = makeFramedBlob(version: 2, payloads: [Data([0x00])])
        record.imagesByteCount = record.imagesBlob.count
        try container.mainContext.save()

        let outcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(outcome, .damaged(.attachmentContainer))
        XCTAssertEqual(store.persistenceAvailability, .available)
    }

    @MainActor
    func testDamagedTargetIsDistinctFromUnavailableAndCanBeDeleted() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()
        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "kept title",
            body: "kept body",
            images: []
        ))
        let record = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        record.targetData = Data([0xff, 0x00, 0xff])
        try container.mainContext.save()

        let damagedOutcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(damagedOutcome, .damaged(.targetMetadata))
        XCTAssertEqual(store.persistenceAvailability, .available)
        XCTAssertTrue(store.delete(accountID: "account", target: target))
        let deletedOutcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(deletedOutcome, .loaded(nil))
    }

    @MainActor
    func testUnreadableAttachmentContainerIsReportedAsDamaged() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()
        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "kept title",
            body: "kept body",
            images: [makeImage(1)]
        ))
        let record = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        record.imagesBlob = Data("not-a-draft-image-container".utf8)
        record.imagesByteCount = record.imagesBlob.count
        try container.mainContext.save()

        let outcome = await store.loadAsync(accountID: "account", target: target)
        XCTAssertEqual(outcome, .damaged(.attachmentContainer))
        XCTAssertEqual(store.persistenceAvailability, .available)
    }

    @MainActor
    func testLegacyByteCountBackfillPreservesVersionTwoBlobBytes() async throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(modelContainer: container)
        let target = makeTarget()
        XCTAssertTrue(store.save(
            accountID: "account",
            target: target,
            title: "title",
            body: "body",
            images: [makeImage(7)]
        ))
        let record = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        let originalBlob = record.imagesBlob
        XCTAssertEqual(
            Data(originalBlob.prefix(5)),
            Data([0x54, 0x50, 0x44, 0x49, 0x02])
        )
        record.imagesByteCount = nil
        try container.mainContext.save()

        let didRepair = await store.repairLegacyMetadataAndPruneAsync()
        XCTAssertTrue(didRepair)
        let repaired = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).first
        )
        XCTAssertEqual(repaired.imagesByteCount, originalBlob.count)
        XCTAssertEqual(repaired.imagesBlob, originalBlob)
    }

    @MainActor
    func testUnavailablePersistenceFailsWithoutMutatingContainer() throws {
        let container = try makeInMemoryModelContainer()
        let store = ContentDraftStore(
            modelContainer: container,
            persistenceAvailability: .unavailable
        )
        let target = makeTarget()
        var loaded: ContentDraft?

        XCTAssertFalse(store.load(accountID: "account", target: target, into: &loaded))
        XCTAssertNil(loaded)
        XCTAssertFalse(store.save(
            accountID: "account",
            target: target,
            title: "",
            body: "body",
            images: []
        ))
        XCTAssertFalse(store.delete(accountID: "account", target: target))
        XCTAssertFalse(store.clear(accountID: "account"))
        XCTAssertEqual(store.persistenceAvailability, .unavailable)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ContentDraftRecord>()).isEmpty)
    }
}
