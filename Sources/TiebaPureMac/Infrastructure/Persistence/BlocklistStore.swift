import Combine
import Foundation

enum BlocklistPersistence {
    static let defaultKey = "io.github.yamakze.TiebaPureMac.blocklist"

    static func loadEntries(
        defaults: UserDefaults = .standard,
        key: String = defaultKey,
        limitPerKind: Int = BlocklistPolicy.maximumEntriesPerKind
    ) -> [BlocklistEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return BlocklistPolicy.sanitized(
            PersistedArrayDecoder.decode(BlocklistEntry.self, from: data) ?? [],
            limitPerKind: limitPerKind
        )
    }
}

@MainActor
final class BlocklistStore: ObservableObject {
    static let shared = BlocklistStore()

    private let defaults: UserDefaults
    private let key: String
    private let limitPerKind: Int
    private let publishSnapshot: (BlocklistSnapshot) -> Void

    @Published private(set) var entries: [BlocklistEntry]

    init(
        defaults: UserDefaults = .standard,
        key: String = BlocklistPersistence.defaultKey,
        limitPerKind: Int = BlocklistPolicy.maximumEntriesPerKind,
        publishSnapshot: @escaping (BlocklistSnapshot) -> Void = TiebaContentFilter.updateBlocklist
    ) {
        self.defaults = defaults
        self.key = key
        self.limitPerKind = max(limitPerKind, 0)
        self.publishSnapshot = publishSnapshot
        entries = BlocklistPersistence.loadEntries(
            defaults: defaults,
            key: key,
            limitPerKind: max(limitPerKind, 0)
        )
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }

    func reload() {
        entries = BlocklistPersistence.loadEntries(
            defaults: defaults,
            key: key,
            limitPerKind: limitPerKind
        )
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }

    func entries(of kind: BlocklistEntryKind) -> [BlocklistEntry] {
        entries.filter { $0.kind == kind }
    }

    func addKeyword(_ keyword: String) {
        add(BlocklistEntry(kind: .keyword, value: keyword, userID: nil))
    }

    func addForum(named name: String) {
        addForum(id: nil, named: name)
    }

    func addForum(id: Int64?, named name: String?) {
        add(
            BlocklistEntry(
                kind: .forum,
                value: name ?? "",
                userID: nil,
                forumID: id
            )
        )
    }

    func addUser(id: Int64?, displayName: String) {
        add(BlocklistEntry(kind: .user, value: displayName, userID: id))
    }

    func isUserBlocked(id: Int64, displayName: String) -> Bool {
        matchingUserEntryIDs(id: id, displayName: displayName).isEmpty == false
    }

    @discardableResult
    func toggleUser(id: Int64, displayName: String) -> Bool {
        let matches = matchingUserEntryIDs(id: id, displayName: displayName)
        guard matches.isEmpty else {
            remove(ids: matches)
            return false
        }
        add(BlocklistEntry(kind: .user, value: displayName, userID: id > 0 ? id : nil))
        return isUserBlocked(id: id, displayName: displayName)
    }

    func remove(_ entry: BlocklistEntry) {
        remove(ids: [entry.id])
    }

    func remove(ids: Set<String>) {
        guard ids.isEmpty == false else { return }
        let updated = entries.filter { ids.contains($0.id) == false }
        guard updated.count != entries.count else { return }
        persist(updated)
    }

    func clear(kind: BlocklistEntryKind) {
        let updated = entries.filter { $0.kind != kind }
        guard updated.count != entries.count else { return }
        persist(updated)
    }

    private func add(_ entry: BlocklistEntry) {
        guard let entry = BlocklistPolicy.normalized(entry) else { return }
        var updated = entries.filter { existing in
            if existing.id == entry.id { return false }
            guard entry.kind == .forum,
                  existing.kind == .forum else { return true }
            if let forumID = entry.forumID,
               let existingForumID = existing.forumID,
               forumID > 0,
               forumID == existingForumID {
                return false
            }
            guard let forumName = entry.forumNameForMatching,
                  let existingForumName = existing.forumNameForMatching else {
                return true
            }
            return forumName != existingForumName
        }
        updated.insert(entry, at: 0)
        persist(BlocklistPolicy.sanitized(updated, limitPerKind: limitPerKind))
    }

    private func matchingUserEntryIDs(id: Int64, displayName: String) -> Set<String> {
        let normalizedName = TiebaUserName.normalized(displayName)
        return Set(entries.compactMap { entry -> String? in
            guard entry.kind == .user else { return nil }
            if let userID = entry.userID {
                if id > 0 && userID == id {
                    return entry.id
                }
            }
            guard normalizedName.isEmpty == false else { return nil }
            return TiebaUserName.normalized(entry.value) == normalizedName ? entry.id : nil
        })
    }

    private func persist(_ updated: [BlocklistEntry]) {
        if updated.isEmpty {
            defaults.removeObject(forKey: key)
            entries = []
        } else {
            guard let data = try? JSONEncoder().encode(updated) else { return }
            defaults.set(data, forKey: key)
            entries = updated
        }
        publishSnapshot(BlocklistSnapshot(entries: entries))
    }
}
