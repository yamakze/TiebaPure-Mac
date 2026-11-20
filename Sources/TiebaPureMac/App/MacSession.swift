import Combine
import Foundation

/// One account owner for all windows. Views own only their navigation and read requests.
@MainActor
final class MacSession: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var isReady = false
    @Published var errorMessage: String?

    let api: any TiebaAPIService
    let accountStore: AccountStore
    private(set) lazy var recentForums = RecentForumStore.shared
    private(set) lazy var searchHistory = SearchHistoryStore.shared
    private let logoutCoordinator: LogoutCoordinator
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
            logoutCoordinator = LogoutCoordinator(accountStore: accountStore, artifactCleaner: ScreenshotSessionCleaner())
            recentForums = RecentForumStore(key: "fixture.recentForums", persistence: ScreenshotHistory<RecentForum>())
            searchHistory = SearchHistoryStore(key: "fixture.searchHistory", persistence: ScreenshotHistory<String>())
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
        logoutCoordinator = LogoutCoordinator(accountStore: store)
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
            self?.account = account
        }.store(in: &subscriptions)
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
