import Foundation

enum ForumThreadCategory: String, CaseIterable, Identifiable, Sendable {
    case replyTime
    case publishTime
    case featured

    var id: Self { self }

    static let timeSortOptions: [Self] = [.replyTime, .publishTime]

    var isTimeSort: Bool { self != .featured }
}
