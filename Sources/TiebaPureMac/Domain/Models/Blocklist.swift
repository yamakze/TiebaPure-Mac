import Foundation

enum BlocklistEntryKind: String, Codable, CaseIterable, Sendable {
    case keyword
    case user
    case forum
}

struct BlocklistEntry: Codable, Equatable, Identifiable, Sendable {
    var kind: BlocklistEntryKind
    // Keyword text, user display name, or forum name depending on kind.
    var value: String
    // User entries added from a profile carry the account id; manual entries
    // stay name-only and match by display name.
    var userID: Int64?
    // Forum entries created from a feed can still be precise when that
    // endpoint omits forum_name. Optional keeps old persisted JSON compatible.
    var forumID: Int64? = nil

    static func forumIDOnlyDisplayValue(_ forumID: Int64) -> String {
        "贴吧 ID \(forumID)"
    }

    var forumNameForMatching: String? {
        guard kind == .forum else { return nil }
        let normalized = TiebaForumName.normalized(value)
        guard normalized.isEmpty == false else { return nil }
        if let forumID,
           normalized == TiebaForumName.normalized(Self.forumIDOnlyDisplayValue(forumID)) {
            return nil
        }
        return normalized
    }

    // Doubles as the dedupe key: one entry per case-folded keyword or forum
    // name, per user id, or per normalized name for name-only user entries.
    var id: String {
        switch kind {
        case .keyword:
            return "keyword:\(value.lowercased())"
        case .forum:
            if let forumID, forumID > 0 {
                return "forum:id:\(forumID)"
            }
            return "forum:name:\(TiebaForumName.normalized(value))"
        case .user:
            if let userID {
                return "user:id:\(userID)"
            }
            return "user:name:\(TiebaUserName.normalized(value))"
        }
    }
}

enum BlocklistPolicy {
    static let maximumEntriesPerKind = 200
    static let maximumKeywordCharacters = 200
    static let maximumUserNameCharacters = 100
    static let maximumForumNameCharacters = 100

    static func normalized(_ entry: BlocklistEntry) -> BlocklistEntry? {
        var normalized = entry
        switch entry.kind {
        case .forum:
            normalized.userID = nil
            if let forumID = entry.forumID, forumID > 0 {
                normalized.forumID = forumID
            } else {
                normalized.forumID = nil
            }
            let name = entry.forumNameForMatching
            if let name, name.isEmpty == false {
                normalized.value = name
            } else if let forumID = normalized.forumID {
                // BlocklistSettingsView displays `value` directly, so retain a
                // readable label even for a rule whose only identity is FID.
                normalized.value = BlocklistEntry.forumIDOnlyDisplayValue(forumID)
            } else {
                normalized.value = ""
            }
        case .keyword, .user:
            normalized.value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.forumID = nil
        }
        let characterLimit: Int
        switch normalized.kind {
        case .keyword:
            characterLimit = maximumKeywordCharacters
        case .user:
            characterLimit = maximumUserNameCharacters
        case .forum:
            characterLimit = maximumForumNameCharacters
        }
        normalized.value = String(normalized.value.prefix(characterLimit))
        if normalized.kind != .user { normalized.userID = nil }
        if let userID = normalized.userID, userID <= 0 {
            normalized.userID = nil
        }
        guard normalized.value.isEmpty == false else { return nil }
        return normalized
    }

    static func sanitized(
        _ entries: [BlocklistEntry],
        limitPerKind: Int = maximumEntriesPerKind
    ) -> [BlocklistEntry] {
        guard limitPerKind > 0 else { return [] }
        var seenIDs = Set<String>()
        var countsByKind: [BlocklistEntryKind: Int] = [:]
        var result: [BlocklistEntry] = []
        for entry in entries {
            guard let entry = normalized(entry),
                  seenIDs.insert(entry.id).inserted,
                  countsByKind[entry.kind, default: 0] < limitPerKind else { continue }
            countsByKind[entry.kind, default: 0] += 1
            result.append(entry)
        }
        return result
    }
}

extension BlocklistSnapshot {
    init(entries: [BlocklistEntry]) {
        var keywords = Set<String>()
        var userIDs = Set<Int64>()
        var userNames = Set<String>()
        var forumIDs = Set<Int64>()
        var forumNames = Set<String>()
        for entry in entries {
            switch entry.kind {
            case .keyword:
                let keyword = entry.value.lowercased()
                if keyword.isEmpty == false { keywords.insert(keyword) }
            case .user:
                if let userID = entry.userID, userID > 0 {
                    userIDs.insert(userID)
                }
                // Keep the normalized name as a fallback even for precise
                // UID-backed entries. Some legacy endpoints omit the UID, and
                // otherwise the same blocked account could reappear there.
                let name = TiebaUserName.normalized(entry.value)
                if name.isEmpty == false { userNames.insert(name) }
            case .forum:
                if let forumID = entry.forumID, forumID > 0 {
                    forumIDs.insert(forumID)
                }
                if let name = entry.forumNameForMatching, name.isEmpty == false {
                    forumNames.insert(name)
                }
            }
        }
        self.init(
            keywords: keywords,
            userIDs: userIDs,
            userNames: userNames,
            forumIDs: forumIDs,
            forumNames: forumNames
        )
    }
}
