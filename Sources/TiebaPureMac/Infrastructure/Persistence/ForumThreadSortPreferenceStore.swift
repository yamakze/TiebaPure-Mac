import Foundation

struct ForumThreadSortPreferenceStore {
    static let storageKey = "io.github.yamakze.TiebaPureMac.forum-thread-sort"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = ForumThreadSortPreferenceStore.storageKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func selection(for forum: Forum) -> ForumThreadCategory {
        var preferences = loadPreferences()
        let forumKey = Self.preferenceKey(for: forum)
        guard let rawValue = preferences[forumKey] else {
            return .replyTime
        }
        guard let category = ForumThreadCategory(rawValue: rawValue),
              category.isTimeSort else {
            preferences.removeValue(forKey: forumKey)
            persist(preferences)
            return .replyTime
        }
        return category
    }

    func select(_ category: ForumThreadCategory, for forum: Forum) {
        guard category.isTimeSort else { return }

        var preferences = loadPreferences()
        let forumKey = Self.preferenceKey(for: forum)
        if category == .replyTime {
            preferences.removeValue(forKey: forumKey)
        } else {
            preferences[forumKey] = category.rawValue
        }
        persist(preferences)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    static func preferenceKey(for forum: Forum) -> String {
        let sourceName = forum.name.isEmpty ? forum.displayName : forum.name
        let normalizedName = TiebaForumName.normalized(sourceName)
        if normalizedName.isEmpty == false {
            return "name:\(normalizedName)"
        }
        return "id:\(forum.id)"
    }

    private func loadPreferences() -> [String: String] {
        guard let stored = defaults.dictionary(forKey: key) else {
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
            }
            return [:]
        }

        var preferences: [String: String] = [:]
        var needsRepair = false
        for (forumKey, value) in stored {
            guard let rawValue = value as? String else {
                needsRepair = true
                continue
            }
            preferences[forumKey] = rawValue
        }
        if needsRepair {
            persist(preferences)
        }
        return preferences
    }

    private func persist(_ preferences: [String: String]) {
        if preferences.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(preferences, forKey: key)
        }
    }
}
