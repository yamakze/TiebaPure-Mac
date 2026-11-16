import CryptoKit
import Foundation

enum LocalThreadListSearchPolicy {
    static func matches(query: String, fields: [String?]) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard terms.isEmpty == false else { return true }

        let searchableText = fields.compactMap { $0 }.joined(separator: "\n")
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]
        return terms.allSatisfy { term in
            searchableText.range(of: term, options: options) != nil
        }
    }
}

enum LocalThreadListSelectionPolicy {
    static func retainedSelection(
        _ selection: Set<Int64>,
        visibleThreadIDs: [Int64]
    ) -> Set<Int64> {
        selection.intersection(Set(visibleThreadIDs))
    }

    static func selectionByTogglingAll(
        _ selection: Set<Int64>,
        visibleThreadIDs: [Int64]
    ) -> Set<Int64> {
        let visible = Set(visibleThreadIDs)
        guard visible.isEmpty == false else { return [] }
        let retained = selection.intersection(visible)
        return retained == visible ? [] : visible
    }
}

struct ThreadReadingPosition: Codable, Equatable, Identifiable, Sendable {
    var threadID: Int64
    var postID: UInt64
    var floor: Int
    var updatedAt: Date

    var id: Int64 { threadID }
}

enum LocalThreadLibraryPolicy {
    static let maximumReadingPositions = 500

    static func readingPosition(
        threadID: Int64,
        postID: UInt64,
        floor: Int,
        updatedAt: Date
    ) -> ThreadReadingPosition? {
        // Restore targets the post ID; floor is display-only and hot-sorted
        // responses legitimately omit it (floor == 0).
        guard threadID > 0, postID > 0, floor >= 0 else { return nil }
        return ThreadReadingPosition(
            threadID: threadID,
            postID: postID,
            floor: floor,
            updatedAt: updatedAt
        )
    }

    static func addingReadingPosition(
        _ position: ThreadReadingPosition,
        to positions: [ThreadReadingPosition],
        limit: Int
    ) -> [ThreadReadingPosition] {
        let effectiveLimit = min(max(limit, 0), maximumReadingPositions)
        guard effectiveLimit > 0 else { return [] }
        var updated = positions.filter { $0.threadID != position.threadID }
        updated.insert(position, at: 0)
        return Array(updated.prefix(effectiveLimit))
    }

    static func sanitizedReadingPositions(
        _ positions: [ThreadReadingPosition],
        limit: Int
    ) -> [ThreadReadingPosition] {
        let effectiveLimit = min(max(limit, 0), maximumReadingPositions)
        guard effectiveLimit > 0 else { return [] }
        var seenThreadIDs = Set<Int64>()
        var result: [ThreadReadingPosition] = []

        let ordered = positions.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.threadID > $1.threadID
        }
        for position in ordered {
            guard position.threadID > 0,
                  position.postID > 0,
                  position.floor >= 0,
                  position.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  seenThreadIDs.insert(position.threadID).inserted else { continue }
            result.append(position)
            if result.count == effectiveLimit { break }
        }

        return result
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumLength))
    }
}

