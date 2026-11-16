import Foundation

enum SearchHistoryPolicy {
    static let maximumStoredEntries = 20
    private static let maximumKeywordLength = 200

    static func normalizedKeyword(_ keyword: String) -> String {
        String(
            keyword
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumKeywordLength)
        )
    }

    static func adding(_ keyword: String, to items: [String], limit: Int) -> [String] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        let normalized = normalizedKeyword(keyword)
        guard normalized.isEmpty == false, effectiveLimit > 0 else {
            return Array(items.prefix(effectiveLimit))
        }
        var updated = items.filter { isSameKeyword($0, normalized) == false }
        updated.insert(normalized, at: 0)
        return Array(updated.prefix(effectiveLimit))
    }

    static func removing(_ keyword: String, from items: [String]) -> [String] {
        let normalized = normalizedKeyword(keyword)
        return items.filter { isSameKeyword($0, normalized) == false }
    }

    static func sanitized(_ items: [String], limit: Int) -> [String] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var result: [String] = []
        for item in items {
            let normalized = normalizedKeyword(item)
            guard normalized.isEmpty == false,
                  result.contains(where: { isSameKeyword($0, normalized) }) == false else {
                continue
            }
            result.append(normalized)
            if result.count == effectiveLimit { break }
        }
        return result
    }

    private static func isSameKeyword(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

