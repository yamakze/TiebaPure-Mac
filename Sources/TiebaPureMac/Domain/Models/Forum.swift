import Foundation

struct Forum: Identifiable, Equatable, Codable, Sendable {
    var id: Int64
    var name: String
    var displayName: String
    var avatarURL: URL?
    var memberCount: Int
    var threadCount: Int

    func refers(to other: Forum) -> Bool {
        if id > 0, other.id > 0 { return id == other.id }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let otherName = other.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !name.isEmpty && name == otherName
    }
}
