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
    private let logoutCoordinator: LogoutCoordinator
    private var subscriptions = Set<AnyCancellable>()
    private var isLoggingOut = false
    private var didStartLoading = false

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("SCREENSHOT_FIXTURES") {
            let arguments = ProcessInfo.processInfo.arguments
            let scenario: FixtureScenario = arguments.contains("SCREENSHOT_EMPTY") ? .empty
                : arguments.contains("SCREENSHOT_ERROR") ? .error : .success
            api = FixtureTiebaAPI(scenario: scenario, delayMilliseconds: arguments.contains("SCREENSHOT_LOADING") ? 60_000 : 0)
            accountStore = AccountStore(service: MemoryAccountStoreService())
            logoutCoordinator = LogoutCoordinator(accountStore: accountStore)
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
        store.accountDidChange.sink { [weak self] account in
            self?.account = account
        }.store(in: &subscriptions)
        monitor.expiredSessions.sink { [weak self] session in
            guard let self, self.account?.sessionIdentity == session, self.isLoggingOut == false else { return }
            Task {
                if await self.logOut() {
                    self.errorMessage = "登录已失效，重新登录后可继续使用账号功能。"
                }
            }
        }.store(in: &subscriptions)
    }

    func load() async {
        guard didStartLoading == false else { return }
        didStartLoading = true
        do {
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
