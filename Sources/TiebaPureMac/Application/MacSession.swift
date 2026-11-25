import Combine
import Foundation
import Observation

enum ReaderSessionError: LocalizedError {
    case alreadySignedIn
    case signInInProgress
    case followUnconfirmed

    var errorDescription: String? {
        switch self {
        case .alreadySignedIn: "已有登录账号。"
        case .signInInProgress: "正在验证另一个登录请求。"
        case .followUnconfirmed: "贴吧尚未确认关注状态已更新。"
        }
    }
}

/// One account owner for all windows. Views own only their navigation and read requests.
@MainActor
@Observable
final class MacSession {
    struct FavoriteChange {
        let session: AccountSessionIdentity
        let threadID: Int64
        let isFavorite: Bool
    }

    private(set) var account: Account?
    private(set) var isReady = false
    var errorMessage: String?

    let api: any TiebaAPIService
    private let accountStore: AccountStore
    @ObservationIgnored private(set) lazy var recentForums = RecentForumStore.shared
    @ObservationIgnored private(set) lazy var searchHistory = SearchHistoryStore.shared
    private(set) var forumSort = ForumThreadSortPreferenceStore()
    private let relationships = SocialRelationshipState()
    private let favoriteChanges = PassthroughSubject<FavoriteChange, Never>()
    var favoriteDidChange: AnyPublisher<FavoriteChange, Never> { favoriteChanges.eraseToAnyPublisher() }
    var forumFollowDidChange: AnyPublisher<ForumFollowChange, Never> {
        relationships.forumFollowDidChange.eraseToAnyPublisher()
    }
    @ObservationIgnored private lazy var social = SocialMutationCoordinator(api: api, state: relationships)
    @ObservationIgnored private lazy var writes = AccountWriteCoordinator(api: api)
    private let artifactCleaner: any SessionArtifactCleaning
    @ObservationIgnored private lazy var logoutCoordinator = LogoutCoordinator(
        accountStore: accountStore,
        artifactCleaner: artifactCleaner,
        beginWriteInvalidation: { [weak self] in
            guard let self else { return }
            self.writesInvalidated = true
            self.social.establishInvalidationBarrier()
            self.writes.establishInvalidationBarrier()
            await self.social.drainInvalidatedOperations()
            await self.writes.drainInvalidatedOperations()
        },
        endWriteInvalidation: { [weak self] in self?.endWriteInvalidation() }
    )
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    private(set) var isLoggingOut = false
    @ObservationIgnored private var writesInvalidated = false
    @ObservationIgnored private var isSigningIn = false
    @ObservationIgnored private var didStartLoading = false

    convenience init(requestBuilder: TiebaRequestBuilder) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("SCREENSHOT_FIXTURES") {
            let arguments = ProcessInfo.processInfo.arguments
            let scenario: FixtureScenario
            if arguments.contains("SCREENSHOT_EMPTY") { scenario = .empty }
            else if arguments.contains("SCREENSHOT_ERROR") { scenario = .error }
            else if arguments.contains("SCREENSHOT_PAGINATION") { scenario = .macReaderRetry }
            else if arguments.contains("SCREENSHOT_REFRESH") { scenario = .refreshUpdate }
            else { scenario = .macReader }
            self.init(
                api: FixtureTiebaAPI(scenario: scenario, delayMilliseconds: arguments.contains("SCREENSHOT_LOADING") ? 60_000 : 0),
                accountStore: AccountStore(service: MemoryAccountStoreService()),
                artifactCleaner: ScreenshotSessionCleaner()
            )
            recentForums = RecentForumStore(persistence: ScreenshotHistory<RecentForum>())
            searchHistory = SearchHistoryStore(persistence: ScreenshotHistory<String>())
            forumSort = ForumThreadSortPreferenceStore(key: "fixture.forum-thread-sort")
            forumSort.reset()
            recentForums.save(FixtureTiebaAPI.forum)
            recentForums.save(FixtureTiebaAPI.forumTwo)
            searchHistory.record("SwiftUI")
            searchHistory.record("macOS")
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
        let api = SessionMonitoringTiebaAPI(
            base: TiebaAPI(
                client: TiebaHTTPClient(session: SecureRemoteURLSession.make(
                    configuration: configuration, redirectScope: .baiduHTTPS
                )),
                requestBuilder: requestBuilder
            ),
            monitor: monitor
        )
        self.init(api: api, accountStore: store, artifactCleaner: LiveSessionArtifactCleaner(),
                  expirationMonitor: monitor)
    }

    init(api: any TiebaAPIService, accountStore: AccountStore, artifactCleaner: any SessionArtifactCleaning,
         expirationMonitor: SessionExpirationMonitor? = nil) {
        self.api = api
        self.accountStore = accountStore
        self.artifactCleaner = artifactCleaner
        observeAccount()
        expirationMonitor?.expiredSessions.sink { [weak self] session in
            Task { [weak self] in
                guard let self, SessionExpirationHandlingPolicy.shouldHandle(
                    reportedSession: session,
                    currentAccount: self.account,
                    expiringSession: self.isLoggingOut ? self.account?.sessionIdentity : nil
                ) else { return }
                if await self.logOut(), self.account == nil {
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
        guard writesInvalidated else { return }
        writesInvalidated = false
        social.endInvalidation()
        writes.endInvalidation()
    }

    func followedForums(account: Account) async throws -> [Forum] {
        let forums = try await api.followedForums(account: account)
        try Task.checkCancellation()
        guard account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        let reconciled = relationships.reconciledFollowedForums(accountID: account.id, loaded: forums)
        relationships.seedFollowedForums(accountID: account.id, forums: reconciled)
        return reconciled
    }

    func forumFollowState(_ forum: Forum, account: Account) async throws -> Bool {
        let membership = try await api.forumMembership(account: account, forum: forum)
        try Task.checkCancellation()
        guard account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        relationships.seedForumFollow(accountID: account.id, forum: forum, isFollowed: membership.isFollowed)
        return relationships.forumFollowOverride(accountID: account.id, forum: forum) ?? membership.isFollowed
    }

    func setForumFollowed(_ forum: Forum, account: Account, followed: Bool) async throws {
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        let membership = try await social.setForumFollowed(account: account, forum: forum, followed: followed)
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        guard membership.isFollowed == followed else { throw ReaderSessionError.followUnconfirmed }
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
        try await writes.setThreadFavorite(account: account, threadID: threadID, forumID: forumID,
                                           postID: postID, isFavorite: isFavorite)
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity else { throw CancellationError() }
        favoriteChanges.send(FavoriteChange(session: account.sessionIdentity, threadID: threadID, isFavorite: isFavorite))
    }

    func reportMutationFailure(_ error: Error, account: Account) {
        guard !isLoggingOut, account.sessionIdentity == self.account?.sessionIdentity,
              !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        errorMessage = ReaderErrorMessage.message(for: error, fallback: "操作未完成。")
    }

    func signIn(cookies: BaiduCookies) async throws {
        guard account == nil else { throw ReaderSessionError.alreadySignedIn }
        guard !isSigningIn, !isLoggingOut else { throw ReaderSessionError.signInInProgress }
        isSigningIn = true
        defer { isSigningIn = false }
        let account = try await api.validateLogin(cookies: cookies)
        try Task.checkCancellation()
        try await accountStore.save(account)
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
        guard account != nil, !isLoggingOut else { return false }
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
