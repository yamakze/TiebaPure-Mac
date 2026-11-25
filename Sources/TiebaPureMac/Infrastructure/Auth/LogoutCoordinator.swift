import Foundation

@MainActor
protocol SessionArtifactCleaning {
    func clear() async throws
}

struct LiveSessionArtifactCleaner: SessionArtifactCleaning {
    func clear() async throws {
        try Task.checkCancellation()
        // The login window uses a nonpersistent WebKit data store.

        HTTPCookieStorage.shared.cookies?
            .filter { Self.isBaiduDomain($0.domain) }
            .forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    private static func isBaiduDomain(_ value: String) -> Bool {
        let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "baidu.com" || domain.hasSuffix(".baidu.com")
    }
}

@MainActor
final class LogoutCoordinator {
    private let accountStore: AccountStore
    private let artifactCleaner: any SessionArtifactCleaning
    private let beginWriteInvalidation: @MainActor () async -> Void
    private let endWriteInvalidation: @MainActor () -> Void

    init(
        accountStore: AccountStore,
        artifactCleaner: any SessionArtifactCleaning,
        beginWriteInvalidation: @escaping @MainActor () async -> Void = {},
        endWriteInvalidation: @escaping @MainActor () -> Void = {}
    ) {
        self.accountStore = accountStore
        self.artifactCleaner = artifactCleaner
        self.beginWriteInvalidation = beginWriteInvalidation
        self.endWriteInvalidation = endWriteInvalidation
    }

    /// AccountStore publishes the signed-out state only after every other
    /// persisted session artifact has been cleared successfully.
    func logOut() async throws {
        await beginWriteInvalidation()
        do {
            try await artifactCleaner.clear()
            try await accountStore.clear()
        } catch {
            endWriteInvalidation()
            throw error
        }
        // Keep writes blocked while signed out. MacSession releases the barrier
        // only after a non-nil account has become the active session.
    }
}
