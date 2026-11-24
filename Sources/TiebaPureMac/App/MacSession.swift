import Combine
import Foundation

/// One account owner for all windows. Views own only their navigation and read requests.
@MainActor
final class MacSession: ObservableObject {
    struct FavoriteChange {
        let session: AccountSessionIdentity
        let threadID: Int64
        let isFavorite: Bool
    }

    private enum LibraryWriteError: LocalizedError {
        case followUnconfirmed
        case favoriteUnconfirmed

        var errorDescription: String? {
            switch self {
            case .followUnconfirmed: "贴吧尚未确认关注状态已更新。"
            case .favoriteUnconfirmed: "贴吧尚未确认收藏状态已更新。"
            }
        }
    }

    @Published private(set) var account: Account?
    @Published private(set) var isReady = false
    @Published var errorMessage: String?

    let api: any TiebaAPIService
    let accountStore: AccountStore
    private(set) lazy var recentForums = RecentForumStore.shared
    private(set) lazy var searchHistory = SearchHistoryStore.shared
    private(set) var forumSort = ForumThreadSortPreferenceStore()
    let relationships = SocialRelationshipState()
    let favoriteDidChange = PassthroughSubject<FavoriteChange, Never>()
    private lazy var social = SocialMutationCoordinator(api: api, state: relationships)
    private lazy var writes = ContentSubmissionCoordinator(api: api)
    private let artifactCleaner: any SessionArtifactCleaning
    private lazy var logoutCoordinator = LogoutCoordinator(
        accountStore: accountStore,
        artifactCleaner: artifactCleaner,
        beginWriteInvalidation: { [weak self] in
            guard let self else { return }
            self.social.establishInvalidationBarrier()
            self.writes.establishInvalidationBarrier()
            await self.social.drainInvalidatedOperations()
            await self.writes.drainInvalidatedOperations()
        },
        endWriteInvalidation: { [weak self] in self?.endWriteInvalidation() }
    )
    private var subscriptions = Set<AnyCancellable>()
    @Published private(set) var isLoggingOut = false
    private var didStartLoading = false

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("SCREENSHOT_FIXTURES") {
            let arguments = ProcessInfo.processInfo.arguments
            let scenario: FixtureScenario
            if arguments.contains("SCREENSHOT_EMPTY") { scenario = .empty }
            else if arguments.contains("SCREENSHOT_ERROR") { scenario = .error }
            else if arguments.contains("SCREENSHOT_PAGINATION") { scenario = .macReaderRetry }
            else if arguments.contains("SCREENSHOT_REFRESH") { scenario = .refreshUpdate }
            else { scenario = .macReader }
            api = FixtureTiebaAPI(scenario: scenario, delayMilliseconds: arguments.contains("SCREENSHOT_LOADING") ? 60_000 : 0)
            accountStore = AccountStore(service: MemoryAccountStoreService())
            artifactCleaner = ScreenshotSessionCleaner()
            recentForums = RecentForumStore(key: "fixture.recentForums", persistence: ScreenshotHistory<RecentForum>())
            searchHistory = SearchHistoryStore(key: "fixture.searchHistory", persistence: ScreenshotHistory<String>())
            forumSort = ForumThreadSortPreferenceStore(key: "fixture.forum-thread-sort")
            forumSort.reset()
            recentForums.save(FixtureTiebaAPI.forum)
            recentForums.save(FixtureTiebaAPI.forumTwo)
            searchHistory.record("SwiftUI")
            searchHistory.record("macOS")
            observeAccount()
            return
        }
#endif
        let store = AccountStore(service: KeychainAccountStoreService())
        let monitor = SessionExpirationMonitor()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        api = SessionMonitoringTiebaAPI(
            base: TiebaAPI(client: TiebaHTTPClient(session: SecureRemoteURLSession.make(
                configuration: configuration, redirectScope: .baiduHTTPS
            ))), monitor: monitor
        )
        accountStore = store
        artifactCleaner = LiveSessionArtifactCleaner()
        observeAccount()
        monitor.expiredSessions.sink { [weak self] session in
            guard let self, self.account?.sessionIdentity == session, self.isLoggingOut == false else { return }
            Task {
                if await self.logOut() {
                    self.errorMessage = "登录已失效，重新登录后可继续使用账号功能。"
                }
            }
        }.store(in: &subscriptions)
    }

    private func observeAccount() {
        accountStore.accountDidChange.sink { [weak self] account in
            guard let self else { return }
            if let previous = self.account, previous.sessionIdentity != account?.sessionIdentity {
                self.relationships.reset(accountID: previous.id)
            }
            if self.account == nil, account != nil { self.endWriteInvalidation() }
            self.account = account
        }.store(in: &subscriptions)
    }

    private func endWriteInvalidation() {
        social.endInvalidation()
        writes.endInvalidation()
    }

    func setForumFollowed(_ forum: Forum, account: Account, followed: Bool) async throws {
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        let membership = try await social.setForumFollowed(account: account, forum: forum, followed: followed)
        guard membership.isFollowed == followed else { throw LibraryWriteError.followUnconfirmed }
    }

    func waitForFavoriteWrites(account: Account) async {
        await writes.waitForThreadFavoriteWrites(account: account)
    }

    func waitForFavoriteWrite(account: Account, threadID: Int64) async {
        await writes.waitForThreadFavoriteWrite(account: account, threadID: threadID)
    }

    func setThreadFavorite(
        account: Account, threadID: Int64, forumID: Int64?, postID: UInt64, isFavorite: Bool
    ) async throws {
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        try await writes.performAccountWrite(account: account, target: .threadFavorite(threadID)) { [api] in
            try await api.setAccountThreadFavorite(account: account, threadID: threadID, postID: postID, favorited: isFavorite)
            try Task.checkCancellation()
            let page = try await api.threadPage(account: account, threadID: threadID, page: 1, forumID: forumID)
            try Task.checkCancellation()
            guard page.isCollected == isFavorite else { throw LibraryWriteError.favoriteUnconfirmed }
        }
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        favoriteDidChange.send(FavoriteChange(session: account.sessionIdentity, threadID: threadID, isFavorite: isFavorite))
    }

    func load() async {
        guard didStartLoading == false else { return }
        didStartLoading = true
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("SCREENSHOT_ACCOUNT"),
               ProcessInfo.processInfo.arguments.contains("SCREENSHOT_FIXTURES") {
                try await accountStore.save(FixtureTiebaAPI.account)
            }
#endif
            account = try await accountStore.load()
        } catch {
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        isReady = true
    }

    @discardableResult
    func logOut() async -> Bool {
        guard isLoggingOut == false else { return false }
        isLoggingOut = true
        defer { isLoggingOut = false }
        do {
            try await logoutCoordinator.logOut()
            return true
        } catch {
            errorMessage = ReaderErrorMessage.message(for: error)
            return false
        }
    }
}
