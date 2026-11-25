@MainActor
enum AppOrderedCollectionPersistence {
    static let browsingHistory = SwiftDataBrowsingHistoryPersistence(
        modelContainer: AppModelContainer.browsingHistory.container,
        persistenceAvailability: AppModelContainer.browsingHistory.availability
    )
    static let recentForums = SwiftDataRecentForumPersistence(
        modelContainer: AppModelContainer.history.container,
        persistenceAvailability: AppModelContainer.history.availability
    )
    static let searchHistory = SwiftDataSearchHistoryPersistence(
        modelContainer: AppModelContainer.history.container,
        persistenceAvailability: AppModelContainer.history.availability
    )
}
