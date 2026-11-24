import Foundation

struct RecentForum: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var displayName: String
    var avatarURL: URL?
    var updatedAt: Date

    var id: String { name.lowercased() }

    init(
        name: String,
        displayName: String,
        avatarURL: URL? = nil,
        updatedAt: Date
    ) {
        self.name = name
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
    }

    var forum: Forum {
        Forum(
            id: 0,
            name: name,
            displayName: displayName,
            avatarURL: avatarURL,
            memberCount: 0,
            threadCount: 0
        )
    }
}

enum RecentForumPolicy {
    static let maximumStoredEntries = 30
    private static let maximumNameLength = 80

    static func sanitized(_ items: [RecentForum], limit: Int) -> [RecentForum] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var seenIDs = Set<String>()
        var result: [RecentForum] = []

        let ordered = items.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        for item in ordered where item.updatedAt.timeIntervalSinceReferenceDate.isFinite {
            let name = normalized(item.name)
            guard name.isEmpty == false else { continue }
            let id = name.lowercased()
            guard seenIDs.insert(id).inserted else { continue }
            let displayName = normalized(item.displayName)
            result.append(RecentForum(
                name: name,
                displayName: displayName.isEmpty ? "\(name)吧" : displayName,
                avatarURL: sanitizedAvatarURL(item.avatarURL),
                updatedAt: item.updatedAt
            ))
            if result.count == effectiveLimit { break }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumNameLength))
    }

    private static func sanitizedAvatarURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https" else {
            return nil
        }
        return TiebaURL.image(url.absoluteString)
    }
}
