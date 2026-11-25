import SwiftUI

struct MacThreadDestination: Identifiable {
    let thread: ThreadSummary
    let matchedPostID: UInt64?
    let markedPostID: UInt64?
    let id: String
    let textPreview: String
    let thumbnails: [URL]

    init(thread: ThreadSummary, matchedPostID: UInt64? = nil, markedPostID: UInt64? = nil) {
        self.thread = thread
        self.matchedPostID = matchedPostID
        self.markedPostID = markedPostID
        id = "\(thread.id)-\(matchedPostID ?? 0)"
        textPreview = thread.textPreview
        thumbnails = Array(thread.blocks.lazy.compactMap { block -> URL? in
            guard case let .image(image) = block else { return nil }
            return image.thumbnailURL ?? image.originalURL
        }.prefix(3))
    }
}

struct MacReaderWorkspace {
    let home = MacReaderSectionState(section: .home)
    let forum = MacReaderSectionState(section: .forum)
    let search = MacReaderSectionState(section: .search)
    let followed = MacReaderSectionState(section: .followedForums)
    let favorites = MacReaderSectionState(section: .favorites)

    subscript(section: ReaderSection) -> MacReaderSectionState {
        switch section {
        case .home: home
        case .forum: forum
        case .search: search
        case .followedForums: followed
        case .favorites: favorites
        }
    }

    var values: [MacReaderSectionState] { [home, forum, search, followed, favorites] }
}

@Observable
final class MacReaderSectionState {
    let id = UUID()
    let section: ReaderSection
    var input = ""
    var query = ""
    var forum: Forum?
    var forumSort = ForumThreadCategory.replyTime
    var onlyFeatured = false
    var searchSort = ThreadSearchOrder.latest
    var searchFocusRequested = false
    private(set) var thread: ThreadReadingState?
    private var showsThread = false
    var pages = ReaderPages<MacThreadDestination>()
    var followed = ReaderPages<Forum>()
    var listPosition: String?
    var followedPosition: Forum.ID?
    var historyError: String?
    var recordsForumVisit = false

    init(section: ReaderSection) {
        self.section = section
        if section == .home || section == .favorites { pages.reload() }
        if section == .followedForums { followed.reload() }
    }

    var canReload: Bool {
        switch section {
        case .forum: forum != nil
        case .search: !query.isEmpty
        case .home, .followedForums, .favorites: true
        }
    }

    var isInForum: Bool { section == .forum && forum != nil }
    var showsForumTopics: Bool { activeThread == nil && isInForum && query.isEmpty }

    var activeThread: ThreadReadingState? { showsThread ? thread : nil }
    var canGoForward: Bool { !showsThread && thread != nil }

    func openThread(_ destination: MacThreadDestination) {
        if thread?.destinationID != destination.id {
            thread = ThreadReadingState(destinationID: destination.id, thread: destination.thread,
                                      initialPostID: destination.matchedPostID ?? destination.markedPostID)
        }
        showsThread = true
    }

    func backToList() { showsThread = false }

    func forwardToThread() { showsThread = thread != nil }

    func discardThread() {
        showsThread = false
        thread = nil
    }

    func reloadThreads() {
        listPosition = nil
        pages.reload(clear: true)
    }

    func openForum(_ forum: Forum, sort: ForumThreadCategory) {
        self.forum = forum
        recordsForumVisit = true
        forumSort = sort
        onlyFeatured = false
        query = ""
        input = ""
        discardThread()
        historyError = nil
        reloadThreads()
    }
}

@Observable
final class ThreadReadingState {
    enum ScrollTarget: Hashable {
        case top
        case post(UInt64)
    }

    let destinationID: String
    let thread: ThreadSummary
    var header: ThreadSummary?
    var forumID: Int64?
    var pages = ReaderPages<Post>()
    var selectedReply: SubpostsReadingState?
    private(set) var onlyAuthor = false
    private(set) var targetPostID: UInt64?
    private var shouldLocateEntryPost = true
    var isFavorite: Bool?
    var isUpdatingFavorite = false
    var scrollPosition: ScrollTarget?

    init(destinationID: String, thread: ThreadSummary, initialPostID: UInt64?) {
        self.destinationID = destinationID
        self.thread = thread
        targetPostID = initialPostID
    }

    var pendingEntryPostID: UInt64? { shouldLocateEntryPost ? targetPostID : nil }

    func reloadFromTop(clear: Bool = false) {
        shouldLocateEntryPost = false
        selectedReply = nil
        scrollPosition = .top
        pages.reload(clear: clear)
    }

    func setOnlyAuthor(_ enabled: Bool) {
        guard onlyAuthor != enabled else { return }
        onlyAuthor = enabled
        targetPostID = nil
        reloadFromTop(clear: true)
    }

    func locateEntryPost(in posts: [Post]) {
        guard let targetPostID = pendingEntryPostID, posts.contains(where: { $0.id == targetPostID }) else { return }
        shouldLocateEntryPost = false
        scrollPosition = .post(targetPostID)
    }
}

@Observable
final class SubpostsReadingState {
    let post: Post
    var pages = ReaderPages<Subpost>()
    var scrollPosition: Subpost.ID?

    init(post: Post) {
        self.post = post
    }
}
