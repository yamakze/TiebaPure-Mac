import Foundation

/// macOS 14+ always uses the application SwiftData container.
@MainActor
struct OrderedCollectionPersistenceBundle {
    let browsingHistory: any BrowsingHistoryPersistence
    let recentForums: any RecentForumPersistence
    let searchHistory: any SearchHistoryPersistence

    init() {
        let container = AppModelContainer.shared
        browsingHistory = SwiftDataBrowsingHistoryPersistence(modelContainer: container)
        recentForums = SwiftDataRecentForumPersistence(modelContainer: container)
        searchHistory = SwiftDataSearchHistoryPersistence(modelContainer: container)
    }
}

@MainActor
enum AppOrderedCollectionPersistence {
    private static let bundle = OrderedCollectionPersistenceBundle()

    static var browsingHistory: any BrowsingHistoryPersistence {
        bundle.browsingHistory
    }

    static var recentForums: any RecentForumPersistence {
        bundle.recentForums
    }

    static var searchHistory: any SearchHistoryPersistence {
        bundle.searchHistory
    }
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

