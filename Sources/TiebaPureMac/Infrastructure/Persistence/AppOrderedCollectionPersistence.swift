import Foundation

/// Each adapter opens on first use. Active history stores do not start the browsing history executor.
@MainActor
enum AppOrderedCollectionPersistence {
    static let browsingHistory = SwiftDataBrowsingHistoryPersistence(
        modelContainer: AppModelContainer.shared.container,
        persistenceAvailability: AppModelContainer.shared.availability
    )
    static let recentForums = SwiftDataRecentForumPersistence(
        modelContainer: AppModelContainer.shared.container,
        persistenceAvailability: AppModelContainer.shared.availability
    )
    static let searchHistory = SwiftDataSearchHistoryPersistence(
        modelContainer: AppModelContainer.shared.container,
        persistenceAvailability: AppModelContainer.shared.availability
    )
}

extension BrowsingHistoryStore {
    convenience init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.browsingHistory",
        limit: Int = BrowsingHistoryPolicy.maximumStoredEntries,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            defaults: defaults,
            key: key,
            limit: limit,
            persistence: AppOrderedCollectionPersistence.browsingHistory,
            faultInjector: faultInjector,
            now: now
        )
    }
}

extension RecentForumStore {
    convenience init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.recentForums",
        limit: Int = RecentForumPolicy.maximumStoredEntries,
        faultInjector: PersistenceFaultInjector = .none,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            defaults: defaults,
            key: key,
            limit: limit,
            persistence: AppOrderedCollectionPersistence.recentForums,
            faultInjector: faultInjector,
            now: now
        )
    }
}

extension SearchHistoryStore {
    convenience init(
        defaults: UserDefaults = .standard,
        key: String = "io.github.yamakze.TiebaPureMac.searchHistory",
        limit: Int = SearchHistoryPolicy.maximumStoredEntries,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        self.init(
            defaults: defaults,
            key: key,
            limit: limit,
            persistence: AppOrderedCollectionPersistence.searchHistory,
            faultInjector: faultInjector
        )
    }
}
