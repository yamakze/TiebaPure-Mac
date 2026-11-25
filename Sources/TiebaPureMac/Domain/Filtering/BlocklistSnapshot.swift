import Foundation

enum TiebaForumName {
    static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("吧") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized.lowercased()
    }
}

// Feed and thread mapping consult the blocklist from async request code, so
// the active rules are a Sendable value swapped behind a lock instead of a
// read of the main-actor BlocklistStore. Keywords and forum names must be
// stored in canonical form, user names folded via TiebaUserName.normalized;
// BlocklistSnapshot(entries:) produces that shape.
struct BlocklistSnapshot: Equatable, Sendable {
    var keywords: Set<String>
    var userIDs: Set<Int64>
    var userNames: Set<String>
    var forumIDs: Set<Int64>
    var forumNames: Set<String>

    init(
        keywords: Set<String> = [],
        userIDs: Set<Int64> = [],
        userNames: Set<String> = [],
        forumIDs: Set<Int64> = [],
        forumNames: Set<String> = []
    ) {
        self.keywords = keywords
        self.userIDs = userIDs
        self.userNames = userNames
        self.forumIDs = Set(forumIDs.filter { $0 > 0 })
        self.forumNames = Set(
            forumNames
                .map(TiebaForumName.normalized)
                .filter { $0.isEmpty == false }
        )
    }

    var isEmpty: Bool {
        keywords.isEmpty
            && userIDs.isEmpty
            && userNames.isEmpty
            && forumIDs.isEmpty
            && forumNames.isEmpty
    }

    func containsKeyword(in text: String) -> Bool {
        guard keywords.isEmpty == false, text.isEmpty == false else { return false }
        let lowercased = text.lowercased()
        return keywords.contains { lowercased.contains($0) }
    }

    func blocksUser(id: Int64, names: [String]) -> Bool {
        if id > 0, userIDs.contains(id) { return true }
        guard userNames.isEmpty == false else { return false }
        return names.contains { name in
            guard name.isEmpty == false else { return false }
            return userNames.contains(TiebaUserName.normalized(name))
        }
    }

    func blocksForum(named name: String) -> Bool {
        blocksForum(id: nil, names: [name])
    }

    func blocksForum(id: Int64?, names: [String]) -> Bool {
        if let id, id > 0, forumIDs.contains(id) {
            return true
        }
        guard forumNames.isEmpty == false else { return false }
        return names.contains { name in
            let normalized = TiebaForumName.normalized(name)
            return normalized.isEmpty == false && forumNames.contains(normalized)
        }
    }
}
