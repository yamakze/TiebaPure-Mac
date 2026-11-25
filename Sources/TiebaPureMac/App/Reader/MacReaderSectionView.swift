import SwiftUI

struct MacReaderSectionView: View {
    @Environment(MacSession.self) private var session
    @Bindable var state: MacReaderSectionState
    let openFollowedForum: (Forum) -> Void

    private struct ForumFollowIdentity: Hashable {
        let session: AccountSessionIdentity
        let name: String
    }

    @State private var searchPresented = false

    private let listContentWidth: CGFloat = 824
    private var section: ReaderSection { state.section }
    private var recentForums: RecentForumStore { session.recentForums }
    private var searchHistory: SearchHistoryStore { session.searchHistory }

    var body: some View {
        Group {
            if let reading = state.activeThread {
                MacThreadView(reading: reading)
                    .id(reading.destinationID)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button("返回", systemImage: "chevron.backward", action: state.backToList)
                                .labelStyle(.iconOnly)
                                .help("返回帖子列表")
                                .accessibilityIdentifier("back-to-thread-list")
                        }
                    }
            } else {
                sectionContent
            }
        }
        .onAppear {
            guard session.account != nil else { return }
            if section == .favorites { state.pages.loadInitialPage() }
            if section == .followedForums { state.followed.loadInitialPage() }
        }
        .task(id: state.pages.request) { [request = state.pages.request] in
            if let request { await loadThreads(request) }
        }
        .task(id: state.followed.request) { [request = state.followed.request] in
            guard let request, let account = session.account else { return }
            do {
                let forums = try await session.followedForums(account: account)
                guard state.followed.request == request else { return }
                if let anchor = state.followedPosition, !forums.contains(where: { $0.id == anchor }) {
                    state.followedPosition = nil
                }
                state.followed.accept(forums, nextPage: nil, for: request)
            } catch {
                if !Task.isCancelled { state.followed.fail(error, for: request) }
            }
        }
    }

    private var sectionContent: some View {
        Group {
            switch section {
            case .home, .favorites:
                threadList
            case .followedForums:
                followedForumList
            case .forum, .search:
                threadList
                    .searchable(text: $state.input, isPresented: $searchPresented, placement: .toolbar,
                                prompt: Text(section == .forum ? (state.forum == nil ? "贴吧名称" : "搜索吧内帖子") : "搜索帖子"))
                    .task(id: state.searchFocusRequested) {
                        guard state.searchFocusRequested else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        searchPresented = true
                        state.searchFocusRequested = false
                    }
                    .onSubmit(of: .search) { submit(state.input) }
                    .onChange(of: state.input) { _, value in
                        if state.isInForum && value.isEmpty && !state.query.isEmpty {
                            state.query = ""
                            state.discardThread()
                            state.reloadThreads()
                        }
                    }
                    .onExitCommand {
                        if state.input.isEmpty { searchPresented = false }
                        else { state.input = "" }
                    }
                    .searchSuggestions {
                        if acceptsThreadSearch && (section == .search || !state.input.isEmpty)
                            && (state.query.isEmpty || state.input != state.query) {
                            let input = state.input
                            let suggestions = searchHistory.items.lazy.filter {
                                input.isEmpty || $0.localizedCaseInsensitiveContains(input)
                            }.prefix(8)
                            ForEach(Array(suggestions), id: \.self) { keyword in
                                Button { submit(keyword) } label: {
                                    Label(keyword, systemImage: "clock")
                                }
                            }
                        }
                    }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if state.isInForum {
                ToolbarItem(placement: .navigation) {
                    Button("返回进吧", systemImage: "chevron.backward") { returnToForumEntry() }
                        .help("返回进吧")
                        .accessibilityIdentifier("back-to-forum-entry")
                }
                if let forum = state.forum, let account = session.account {
                    ToolbarItem(placement: .primaryAction) {
                        MacForumFollowButton(forum: forum, account: account)
                            .id(ForumFollowIdentity(session: account.sessionIdentity, name: forum.name))
                    }
                }
            }
        }
    }

    private var acceptsThreadSearch: Bool { section == .search || state.isInForum }
    private var forumCategory: ForumThreadCategory { state.onlyFeatured ? .featured : state.forumSort }

    private var navigationTitle: String {
        if section == .forum, let forum = state.forum {
            return state.query.isEmpty ? forum.displayName : "\(forum.displayName) · 搜索"
        }
        return section.rawValue
    }

    private var threadList: some View {
        Group {
            if (section == .forum || section == .search) && !state.canReload {
                history
            } else if state.pages.items.isEmpty && state.pages.nextPage == nil {
                if state.pages.request != nil || state.pages.error != nil {
                    ReaderPageFooter(loading: state.pages.request != nil, error: state.pages.error, nextPage: nil,
                                     loadNext: {}, retry: { state.pages.retry() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let title = !state.query.isEmpty ? "没有搜索结果" : section == .favorites ? "暂无收藏" : "暂无帖子"
                    ContentUnavailableView(title, systemImage: section.icon)
                }
            } else {
                ReaderScrollView(position: $state.listPosition, contentWidth: listContentWidth) {
                    LazyVStack(spacing: 0) {
                        ForEach(state.pages.items) { destination in
                            VStack(spacing: 0) {
                                Button {
                                    searchPresented = false
                                    state.openThread(destination)
                                } label: {
                                    MacThreadRow(destination: destination,
                                                 forumCategory: state.isInForum && state.query.isEmpty ? forumCategory : nil)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("thread-\(destination.id)")
                                Divider()
                            }
                        }
                        ReaderPageFooter(loading: state.pages.request != nil, error: state.pages.error,
                                         nextPage: state.pages.nextPage, loadNext: { state.pages.loadNext() },
                                         retry: { state.pages.retry() })
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 24, for: .scrollContent)
                .accessibilityIdentifier("reader-thread-list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let historyError = state.historyError {
                Text(historyError).font(.callout).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    private var followedForumList: some View {
        Group {
            if state.followed.items.isEmpty && state.followed.request == nil && state.followed.error == nil {
                ContentUnavailableView("暂无关注的吧", systemImage: ReaderSection.followedForums.icon)
            } else {
                ReaderScrollView(position: $state.followedPosition, contentWidth: listContentWidth) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(state.followed.items) { forum in
                            Button { openFollowedForum(forum) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Color.accentColor.opacity(0.12)
                                        if let url = forum.avatarURL {
                                            MacRemoteImage(url: url, maximumPixelSize: 96, contentMode: .fill,
                                                           placeholder: "square.grid.2x2")
                                        } else {
                                            Text(forum.displayName.prefix(1))
                                                .font(.headline)
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    .frame(width: 38, height: 38)
                                    .clipShape(.rect(cornerRadius: 9))
                                    .accessibilityHidden(true)
                                    Text(forum.displayName)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("followed-forum-\(forum.id)")
                        }
                    }
                    .scrollTargetLayout()
                    ReaderPageFooter(loading: state.followed.request != nil, error: state.followed.error, nextPage: nil,
                                     loadNext: {}, retry: { state.followed.retry() })
                }
                .contentMargins(24, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(section == .forum ? "最近访问" : "历史搜索词",
                          systemImage: section == .forum ? "clock" : "magnifyingglass")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if section == .search && !searchHistory.items.isEmpty {
                        Button("清空历史") {
                            state.historyError = searchHistory.clear() ? nil : "无法清空搜索历史。"
                        }
                    }
                }
                if section == .forum {
                    if recentForums.items.isEmpty {
                        Text(recentForums.persistenceAvailability.canPersist ? "暂无访问记录" : "访问记录不可用")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(recentForums.items) { forum in
                                Button { openForum(forum.forum) } label: {
                                    HStack(spacing: 8) {
                                        Text(forum.displayName.prefix(1))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tint)
                                            .frame(width: 24, height: 24)
                                            .background(Color.accentColor.opacity(0.12), in: Circle())
                                            .accessibilityHidden(true)
                                        Text(forum.displayName).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .controlSize(.large)
                            }
                        }
                    }
                } else {
                    if searchHistory.items.isEmpty {
                        Text(searchHistory.persistenceAvailability.canPersist ? "暂无搜索记录" : "搜索历史不可用")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchHistory.items, id: \.self) { keyword in
                            Button { submit(keyword) } label: {
                                Label(keyword, systemImage: "clock")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除此记录", systemImage: "trash", role: .destructive) {
                                    state.historyError = searchHistory.remove(keyword) ? nil : "无法删除搜索记录。"
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func submit(_ text: String) {
        if section == .forum && state.forum == nil {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            openForum(Forum(id: 0, name: name, displayName: name.hasSuffix("吧") ? name : "\(name)吧",
                            avatarURL: nil, memberCount: 0, threadCount: 0))
            return
        }
        let value = SearchHistoryPolicy.normalizedKeyword(text)
        guard !value.isEmpty else { return }
        state.input = value
        state.query = value
        searchPresented = false
        state.discardThread()
        state.historyError = nil
        if section == .search && !searchHistory.record(value) {
            state.historyError = "无法保存搜索历史。"
        }
        state.reloadThreads()
    }

    private func openForum(_ forum: Forum) {
        searchPresented = false
        state.openForum(forum, sort: session.forumSort.selection(for: forum))
    }

    private func returnToForumEntry() {
        searchPresented = false
        state.forum = nil
        state.recordsForumVisit = false
        state.input = ""
        state.query = ""
        state.historyError = nil
        state.discardThread()
        state.pages = ReaderPages()
        state.listPosition = nil
    }

    @MainActor
    private func loadThreads(_ request: ReaderPages<MacThreadDestination>.Request) async {
        guard state.pages.request == request else { return }
        let page = request.page
        let section = section
        let account = session.account
        let forum = state.forum
        let query = state.query
        do {
            let incoming: [MacThreadDestination]
            let next: Int?
            switch (section, query.isEmpty) {
            case (.search, false), (.forum, false):
                let result = try await session.api.searchThreads(keyword: query, page: page, order: state.searchSort,
                                                                 forumName: forum?.name)
                incoming = result.results.map { MacThreadDestination(thread: $0.threadSummary, matchedPostID: $0.postID) }
                next = result.hasMore ? max(page, result.currentPage) + 1 : nil
            case (.home, _):
                let result = try await session.api.personalizedThreads(account: account, page: page, loadType: page == 1 ? 1 : 2)
                incoming = result.threads.map { MacThreadDestination(thread: $0) }
                next = result.hasMore ? page + 1 : nil
            case (.forum, true):
                guard let forum else { return }
                let result = try await session.api.forumThreads(account: account, forumName: forum.name, page: page, category: forumCategory)
                incoming = result.threads.map { MacThreadDestination(thread: $0) }
                next = result.hasMore ? page + 1 : nil
            case (.favorites, _):
                guard let account else { return }
                await session.waitForFavoriteWrites(account: account)
                try Task.checkCancellation()
                let result = try await session.api.accountThreadFavorites(account: account, page: page)
                incoming = result.favorites.map { favorite in
                    let thread = ThreadSummary(
                        id: favorite.threadID, forumID: favorite.forumID, title: favorite.title,
                        author: UserSummary(id: 0, name: "", displayName: favorite.authorDisplayName, portrait: ""),
                        forumName: favorite.forumName, replyCount: favorite.replyCount, viewCount: 0,
                        lastReplyAt: favorite.lastReplyAt, blocks: []
                    )
                    return MacThreadDestination(thread: thread, markedPostID: favorite.markedPostID)
                }
                next = result.hasMore ? max(page, result.currentPage) + 1 : nil
            case (.followedForums, _), (.search, true):
                return
            }
            try Task.checkCancellation()
            guard state.pages.request == request, account?.sessionIdentity == session.account?.sessionIdentity else { return }
            if request.replacesItems, let anchor = state.listPosition, !incoming.contains(where: { $0.id == anchor }) {
                state.listPosition = nil
            }
            state.pages.accept(incoming, nextPage: next, for: request)
            if section == .forum, query.isEmpty, let forum {
                let resolved = incoming.first?.thread.forumRoute ?? forum
                if request.replacesItems || state.recordsForumVisit { state.forum = resolved }
                if state.recordsForumVisit && (!incoming.isEmpty || next == nil) {
                    let saved = recentForums.save(resolved)
                    state.recordsForumVisit = !saved
                    state.historyError = saved ? nil : "无法保存访问记录。"
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            state.pages.fail(error, for: request)
        }
    }
}
