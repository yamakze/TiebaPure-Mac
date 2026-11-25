import Foundation

enum AccountWriteError: LocalizedError {
    case operationInProgress
    case sessionTransition
    case favoriteUnconfirmed

    var errorDescription: String? {
        switch self {
        case .operationInProgress: "操作正在处理中。"
        case .sessionTransition: "账号状态正在切换。"
        case .favoriteUnconfirmed: "贴吧尚未确认收藏状态已更新。"
        }
    }
}

@MainActor
final class AccountWriteCoordinator {
    enum AccountWriteTarget: Hashable, Sendable {
        case profile
        case deleteThread(Int64)
        case threadFavorite(Int64)
    }

    private struct AccountWriteKey: Hashable, Sendable {
        let session: AccountSessionIdentity
        let target: AccountWriteTarget

        var accountID: String { session.accountID }
    }

    private struct AccountWrite {
        let id: UUID
        let task: Task<Void, Error>
    }

    private let api: any TiebaAPIService
    private var accountWrites: [AccountWriteKey: AccountWrite] = [:]
    private var globalInvalidationCount = 0
    private var accountInvalidationCounts: [String: Int] = [:]

    init(api: any TiebaAPIService) {
        self.api = api
    }

    func isInvalidating(accountID: String) -> Bool {
        !canWrite(accountID: accountID)
    }

    func setThreadFavorite(
        account: Account, threadID: Int64, forumID: Int64?, postID: UInt64, isFavorite: Bool
    ) async throws {
        try await performAccountWrite(account: account, target: .threadFavorite(threadID)) { [api] in
            try await api.setAccountThreadFavorite(account: account, threadID: threadID, postID: postID, favorited: isFavorite)
            try Task.checkCancellation()
            let page = try await api.threadPage(account: account, threadID: threadID, page: 1, forumID: forumID)
            try Task.checkCancellation()
            guard page.isCollected == isFavorite else { throw AccountWriteError.favoriteUnconfirmed }
        }
    }

    /// Registers account mutations with the session barrier. The stored task survives a view
    /// dismissal, but session invalidation cancels and drains it before account
    /// artifacts are cleared.
    func performAccountWrite(
        account: Account,
        target: AccountWriteTarget,
        coalescesConcurrentCalls: Bool = false,
        operation: @escaping () async throws -> Void
    ) async throws {
        guard canWrite(accountID: account.id) else {
            throw AccountWriteError.sessionTransition
        }

        let key = AccountWriteKey(session: account.sessionIdentity, target: target)
        if let existing = accountWrites[key] {
            guard coalescesConcurrentCalls else {
                throw AccountWriteError.operationInProgress
            }
            return try await existing.task.value
        }

        let id = UUID()
        let task = Task {
            try await operation()
        }
        accountWrites[key] = AccountWrite(id: id, task: task)

        do {
            try await task.value
            finishAccountWrite(id: id, for: key)
        } catch {
            finishAccountWrite(id: id, for: key)
            throw error
        }
    }

    /// Read screens wait for outstanding favorite writes before asking the
    /// service for an authoritative list. This closes the leave-and-reenter
    /// race without cancelling a write that may already have reached Baidu.
    func waitForThreadFavoriteWrites(account: Account) async {
        let session = account.sessionIdentity
        while true {
            let matching = accountWrites.filter { key, _ in
                key.session == session && key.target.isThreadFavorite
            }
            guard matching.isEmpty == false else { return }
            for write in matching.values {
                _ = await write.task.result
            }
            for (key, write) in matching {
                finishAccountWrite(id: write.id, for: key)
            }
        }
    }

    func waitForThreadFavoriteWrite(account: Account, threadID: Int64) async {
        let key = AccountWriteKey(
            session: account.sessionIdentity,
            target: .threadFavorite(threadID)
        )
        while let write = accountWrites[key] {
            _ = await write.task.result
            finishAccountWrite(id: write.id, for: key)
        }
    }

    /// Closes the matching account write entry point synchronously. Callers that
    /// coordinate multiple write domains must establish every barrier before
    /// awaiting any drain operation.
    func establishInvalidationBarrier(accountID: String? = nil) {
        if let accountID {
            accountInvalidationCounts[accountID, default: 0] += 1
        } else {
            globalInvalidationCount += 1
        }
    }

    /// Cancels and drains writes covered by an already-established barrier.
    func drainInvalidatedOperations(accountID: String? = nil) async {
        await drainOperations(accountID: accountID)
    }

    /// Closes the matching account write entry point before draining active writes.
    /// The barrier remains active until the matching `endInvalidation` call.
    func beginInvalidation(accountID: String? = nil) async {
        establishInvalidationBarrier(accountID: accountID)
        await drainInvalidatedOperations(accountID: accountID)
    }

    func endInvalidation(accountID: String? = nil) {
        if let accountID {
            guard let count = accountInvalidationCounts[accountID] else { return }
            if count > 1 {
                accountInvalidationCounts[accountID] = count - 1
            } else {
                accountInvalidationCounts[accountID] = nil
            }
        } else {
            globalInvalidationCount = max(0, globalInvalidationCount - 1)
        }
    }

    private func finishAccountWrite(id: UUID, for key: AccountWriteKey) {
        guard accountWrites[key]?.id == id else { return }
        accountWrites[key] = nil
    }

    private func canWrite(accountID: String) -> Bool {
        globalInvalidationCount == 0 && accountInvalidationCounts[accountID] == nil
    }

    private func drainOperations(accountID: String?) async {
        let matching = accountWrites.filter { key, _ in
            accountID == nil || key.accountID == accountID
        }
        matching.values.forEach { $0.task.cancel() }
        for (key, write) in matching {
            _ = await write.task.result
            finishAccountWrite(id: write.id, for: key)
        }
    }
}

private extension AccountWriteCoordinator.AccountWriteTarget {
    var isThreadFavorite: Bool {
        if case .threadFavorite = self { return true }
        return false
    }
}
