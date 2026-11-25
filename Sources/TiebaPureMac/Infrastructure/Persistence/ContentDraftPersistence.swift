import Foundation

enum ContentDraftPersistenceError: Error { case unavailable }

@MainActor
protocol ContentDraftPersistenceBackend: AnyObject {
    var persistenceAvailability: PersistenceAvailability { get }

    func load(
        accountID: String,
        target: ContentSubmissionTarget,
        into draft: inout ContentDraft?
    ) -> Bool
    func loadAsync(
        accountID: String,
        target: ContentSubmissionTarget
    ) async -> ContentDraftLoadOutcome
    func save(_ draft: ContentDraft) -> Bool
    func saveAsync(_ draft: ContentDraft) async throws
    func delete(accountID: String, target: ContentSubmissionTarget) -> Bool
    func clear(accountID: String) -> Bool
}

extension ContentDraftPersistenceBackend {
    func draft(accountID: String, target: ContentSubmissionTarget) -> ContentDraft? {
        var loaded: ContentDraft?
        guard load(accountID: accountID, target: target, into: &loaded) else { return nil }
        return loaded
    }
}

@MainActor
final class UnavailableContentDraftPersistenceBackend: ContentDraftPersistenceBackend {
    let persistenceAvailability: PersistenceAvailability = .unavailable

    func load(
        accountID: String,
        target: ContentSubmissionTarget,
        into draft: inout ContentDraft?
    ) -> Bool {
        draft = nil
        return false
    }

    func loadAsync(
        accountID: String,
        target: ContentSubmissionTarget
    ) async -> ContentDraftLoadOutcome {
        .unavailable
    }

    func save(_ draft: ContentDraft) -> Bool { false }

    func saveAsync(_ draft: ContentDraft) async throws {
        throw ContentDraftPersistenceError.unavailable
    }

    func delete(accountID: String, target: ContentSubmissionTarget) -> Bool { false }
    func clear(accountID: String) -> Bool { false }
}
