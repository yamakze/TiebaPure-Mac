import SwiftUI

private struct MacThreadDestination: Identifiable, Hashable {
    let thread: ThreadSummary
    var matchedPostID: UInt64? = nil
    var markedPostID: UInt64? = nil
    var id: String { "\(thread.id)-\(matchedPostID ?? 0)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MacReaderView: View {
    @EnvironmentObject private var session: MacSession
    @ObservedObject var recentForums: RecentForumStore
    @ObservedObject var searchHistory: SearchHistoryStore

    @State private var section: ReaderSection = .home
    @State private var input = ""
    @State private var query = ""
    @State private var forum: Forum?
    @State private var forumSort = ForumThreadCategory.replyTime
    @State private var onlyFeatured = false
    @State private var searchSort = ReaderSearchSort.latest
    @State private var searchPresented = false
    @State private var searchFocusRequest: UUID?
    @State private var path: [MacThreadDestination] = []
    @State private var forwardDestination: MacThreadDestination?
    @State private var pages = ReaderPages<MacThreadDestination>()
    @State private var followed = ReaderPages<Forum>()
    @State private var threadReload = UUID()
    @State private var showsLogin = false
    @State private var showsProfile = false
    @State private var historyError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<ReaderSection?>(
                get: { section }, set: { if let value = $0 { show(value) } }
            )) {
                ForEach(ReaderSection.allCases.filter { !$0.requiresAccount }) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                        .accessibilityIdentifier("section-\(item.id)")
                }
                if session.account != nil {
                    Section("账号") {
                        ForEach(ReaderSection.allCases.filter(\.requiresAccount)) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                                .accessibilityIdentifier("section-\(item.id)")
                        }
                    }
                }
            }
            .navigationTitle("TiebaPure-Mac")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom, spacing: 0) { accountBar }
        } detail: {
            NavigationStack(path: Binding(
                get: { path }, set: { next in
                    forwardDestination = next.isEmpty ? path.last : nil
                    path = next
                }
            )) {
                Group {
                    switch section {
                    case .home, .favorites:
                        threadList
                    case .followedForums:
                        followedForumList
                    case .forum, .search:
                        threadList
                            .searchable(text: $input, isPresented: $searchPresented, placement: .toolbar,
                                        prompt: Text(section == .forum ? (forum == nil ? "贴吧名称" : "搜索吧内帖子") : "搜索帖子"))
                            .task(id: searchFocusRequest) {
                                guard section == .forum || section == .search,
                                      path.isEmpty, searchFocusRequest != nil else { return }
                                searchFocusRequest = nil
                                searchPresented = true
                            }
                            .onSubmit(of: .search) { submit(input) }
                            .onChange(of: input) { _, value in
                                if isInForum && value.isEmpty && !query.isEmpty {
                                    query = ""
                                    forwardDestination = nil
                                    pages.reload(clear: true)
                                }
                            }
                            .onExitCommand {
                                if input.isEmpty { searchPresented = false }
                                else { input = "" }
                            }
                            .searchSuggestions {
                                if acceptsThreadSearch && (section == .search || !input.isEmpty)
                                    && (query.isEmpty || input != query) {
                                    ForEach(searchHistory.items.filter {
                                        input.isEmpty || $0.localizedCaseInsensitiveContains(input)
                                    }.prefix(8), id: \.self) { keyword in
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
                    if isInForum && path.isEmpty {
                        ToolbarItem(placement: .navigation) {
                            Button("返回进吧", systemImage: "chevron.backward") { show(.forum) }
                                .help("返回进吧")
                                .accessibilityIdentifier("back-to-forum-entry")
                        }
                        if let forum, let account = session.account {
                            ToolbarItem(placement: .primaryAction) {
                                MacForumFollowButton(forum: forum, account: account)
                                    .id(account.sessionIdentity)
                                    .id(forum.name)
                            }
                        }
                    }
                }
                .navigationDestination(for: MacThreadDestination.self) { destination in
                    MacThreadView(thread: destination.thread,
                                  initialPostID: destination.matchedPostID ?? destination.markedPostID, reloadID: threadReload)
                }
            }
        }
        .focusedSceneValue(\.macReaderActions, MacReaderActions(
            show: show,
            find: {
                if section != .forum && section != .search { show(.search) }
                path = []
                searchFocusRequest = UUID()
            },
            reload: canReload ? reload : nil,
            back: path.isEmpty ? nil : {
                forwardDestination = path.popLast()
            },
            forward: path.isEmpty && forwardDestination != nil ? {
                if let forwardDestination { path = [forwardDestination] }
                forwardDestination = nil
            } : nil,
            searchSort: path.isEmpty && (section == .search || (isInForum && !query.isEmpty)) ? Binding(
                get: { searchSort },
                set: { value in
                    guard searchSort != value else { return }
                    searchSort = value
                    if !query.isEmpty {
                        forwardDestination = nil
                        pages.reload(clear: true)
                    }
                }
            ) : nil,
            forumSort: showsForumTopics ? Binding(
                get: { forumSort },
                set: { value in
                    guard let forum, forumSort != value else { return }
                    session.forumSort.select(value, for: forum)
                    forumSort = value
                    forwardDestination = nil
                    pages.reload(clear: true)
                }
            ) : nil,
            onlyFeatured: showsForumTopics ? Binding(
                get: { onlyFeatured },
                set: { value in
                    guard onlyFeatured != value else { return }
                    onlyFeatured = value
                    forwardDestination = nil
                    pages.reload(clear: true)
                }
            ) : nil
        ))
        .onChange(of: session.account?.sessionIdentity) { _, _ in
            path = []
            forwardDestination = nil
            if section.requiresAccount && session.account == nil {
                show(.home)
            } else if section == .followedForums {
                followed.reload(clear: true)
            } else if canReload {
                pages.reload(clear: true)
            }
        }
        .task(id: pages.request) { [request = pages.request] in
            if let request { await loadThreads(request) }
        }
        .task(id: followed.request) { [request = followed.request] in
            guard let request, let account = session.account else { return }
            do {
                let forums = try await session.api.followedForums(account: account)
                try Task.checkCancellation()
                guard account.sessionIdentity == session.account?.sessionIdentity else { return }
                let reconciled = session.relationships.reconciledFollowedForums(accountID: account.id, loaded: forums)
                session.relationships.seedFollowedForums(accountID: account.id, forums: reconciled)
                followed.accept(reconciled, nextPage: nil, for: request)
            } catch {
                if !Task.isCancelled { followed.fail(error, for: request) }
            }
        }
        .onReceive(session.relationships.forumFollowDidChange) { change in
            if section == .followedForums, change.accountID == session.account?.id { followed.reload(clear: true) }
        }
        .onReceive(session.favoriteDidChange) { change in
            if section == .favorites, change.session == session.account?.sessionIdentity { pages.reload(clear: true) }
        }
        .onAppear {
            if section == .home && pages.items.isEmpty && pages.request == nil && pages.error == nil {
                pages.reload()
            }
        }
        .sheet(isPresented: $showsLogin) { MacLoginView() }
        .alert("账号状态", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("好") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }

    private var canReload: Bool {
        switch section {
        case .home: true
        case .forum: forum != nil
        case .search: !query.isEmpty
        case .followedForums, .favorites: session.account != nil
        }
    }

    private var isInForum: Bool { section == .forum && forum != nil }
    private var acceptsThreadSearch: Bool { section == .search || isInForum }
    private var showsForumTopics: Bool { path.isEmpty && isInForum && query.isEmpty }
    private var forumCategory: ForumThreadCategory { onlyFeatured ? .featured : forumSort }

    private var navigationTitle: String {
        if section == .forum, let forum {
            return query.isEmpty ? forum.displayName : "\(forum.displayName) · 搜索"
        }
        return section.rawValue
    }

    private var threadList: some View {
        let prefetchID = pages.items.dropLast(2).last?.id
        return Group {
            if (section == .forum || section == .search) && !canReload {
                history
            } else if pages.items.isEmpty && pages.nextPage == nil {
                if pages.request != nil || pages.error != nil {
                    ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: nil,
                                     loadNext: {}, retry: { pages.retry() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let title = !query.isEmpty ? "没有搜索结果" : section == .favorites ? "暂无收藏" : "暂无帖子"
                    ContentUnavailableView(title, systemImage: section.icon)
                }
            } else {
                let rowInsets = EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24)
                List {
                    ForEach(pages.items) { destination in
                        NavigationLink(value: destination) {
                            MacThreadRow(thread: destination.thread, forumCategory: isInForum && query.isEmpty ? forumCategory : nil)
                        }
                        .listRowInsets(rowInsets)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                        .accessibilityIdentifier("thread-\(destination.id)")
                        .onAppear {
                            if destination.id == prefetchID { pages.loadNext() }
                        }
                    }
                    if pages.request != nil || pages.error != nil || pages.nextPage != nil {
                        ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: pages.nextPage,
                                         loadNext: { pages.loadNext() }, retry: { pages.retry() })
                            .listRowInsets(rowInsets)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: 872)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let historyError {
                Text(historyError).font(.callout).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    private var followedForumList: some View {
        Group {
            if followed.items.isEmpty && followed.request == nil && followed.error == nil {
                ContentUnavailableView("暂无关注的吧", systemImage: ReaderSection.followedForums.icon)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(followed.items) { forum in
                            Button { openForum(forum) } label: {
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
                    ReaderPageFooter(loading: followed.request != nil, error: followed.error, nextPage: nil,
                                     loadNext: {}, retry: { followed.retry() })
                }
                .contentMargins(24, for: .scrollContent)
                .frame(maxWidth: 872)
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
                            historyError = searchHistory.clear() ? nil : "无法清空搜索历史。"
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
                                    historyError = searchHistory.remove(keyword) ? nil : "无法删除搜索记录。"
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

    private var accountBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                MacAccountAvatar(url: session.account?.portraitURL)
                if let account = session.account {
                    Text(account.displayName.isEmpty ? account.name : account.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        Button("个人主页") { showsProfile = true }
                        Button("退出登录", role: .destructive) { Task { await session.logOut() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(session.isLoggingOut)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("账号菜单")
                    .accessibilityIdentifier("account-menu")
                    .popover(isPresented: $showsProfile, arrowEdge: .top) {
                        MacAccountProfile(account: account)
                            .id(account.sessionIdentity)
                    }
                } else {
                    Button("登录") { showsLogin = true }
                        .accessibilityIdentifier("account-login")
                    Spacer(minLength: 0)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private func show(_ destination: ReaderSection) {
        guard !destination.requiresAccount || session.account != nil else { return }
        guard section != destination || (destination == .forum && isInForum) else { return }
        section = destination
        input = ""
        query = ""
        forum = nil
        searchPresented = false
        searchFocusRequest = nil
        path = []
        forwardDestination = nil
        historyError = nil
        pages = ReaderPages()
        followed = ReaderPages()
        if destination == .home || destination == .favorites { pages.reload() }
        if destination == .followedForums { followed.reload() }
    }

    private func submit(_ text: String) {
        if section == .forum && forum == nil {
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            openForum(Forum(id: 0, name: name, displayName: name.hasSuffix("吧") ? name : "\(name)吧",
                            avatarURL: nil, memberCount: 0, threadCount: 0))
            return
        }
        let value = SearchHistoryPolicy.normalizedKeyword(text)
        guard !value.isEmpty else { return }
        input = value
        query = value
        searchPresented = false
        forwardDestination = nil
        historyError = nil
        if section == .search && !searchHistory.record(value) {
            historyError = "无法保存搜索历史。"
        }
        pages.reload(clear: true)
    }

    private func openForum(_ forum: Forum) {
        if section != .forum { show(.forum) }
        self.forum = forum
        forumSort = session.forumSort.selection(for: forum)
        onlyFeatured = false
        query = ""
        input = ""
        searchPresented = false
        forwardDestination = nil
        historyError = nil
        pages.reload(clear: true)
    }

    private func reload() {
        if !path.isEmpty { threadReload = UUID() }
        else if section == .followedForums { followed.reload() }
        else { pages.reload() }
    }

    @MainActor
    private func loadThreads(_ request: ReaderPages<MacThreadDestination>.Request) async {
        guard pages.request == request else { return }
        let page = request.page
        let section = section
        let account = session.account
        let forum = forum
        let query = query
        do {
            let incoming: [MacThreadDestination]
            let next: Int?
            switch (section, query.isEmpty) {
            case (.search, false), (.forum, false):
                let result = try await session.api.searchThreads(keyword: query, page: page, sortType: searchSort.rawValue,
                                                                 forumName: forum?.name)
                incoming = result.results.map { MacThreadDestination(thread: $0.threadSummary, matchedPostID: $0.postID) }
                next = result.hasMore ? max(page, result.currentPage) + 1 : nil
            case (.home, _):
                incoming = try await session.api.personalizedThreads(account: account, page: page, loadType: page == 1 ? 1 : 2)
                    .map { MacThreadDestination(thread: $0) }
                next = incoming.isEmpty ? nil : page + 1
            case (.forum, true):
                guard let forum else { return }
                incoming = try await session.api.forumThreads(account: account, forumName: forum.name, page: page, category: forumCategory)
                    .map { MacThreadDestination(thread: $0) }
                next = incoming.isEmpty ? nil : page + 1
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
            guard pages.request == request, account?.sessionIdentity == session.account?.sessionIdentity else { return }
            pages.accept(incoming, nextPage: next, for: request)
            if section == .forum, query.isEmpty, request.replacesItems, let forum {
                let resolved = incoming.first?.thread.forumRoute ?? forum
                self.forum = resolved
                if !recentForums.save(resolved) {
                    historyError = "无法保存访问记录。"
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            pages.fail(error, for: request)
        }
    }
}

private struct MacForumFollowButton: View {
    @EnvironmentObject private var session: MacSession
    let forum: Forum
    let account: Account

    @State private var isFollowed: Bool?
    @State private var readError: String?
    @State private var readRequest = UUID()
    @State private var isWriting = false

    var body: some View {
        Group {
            if let isFollowed {
                Button(isFollowed ? "已关注" : "关注") {
                    isWriting = true
                    Task {
                        defer { isWriting = false }
                        do {
                            try await session.setForumFollowed(forum, account: account, followed: !isFollowed)
                            try Task.checkCancellation()
                            if account.sessionIdentity == session.account?.sessionIdentity { self.isFollowed = !isFollowed }
                        } catch is CancellationError {
                        } catch {
                            if account.sessionIdentity == session.account?.sessionIdentity {
                                session.errorMessage = ReaderErrorMessage.message(for: error)
                            }
                        }
                    }
                }
                .disabled(isWriting || session.isLoggingOut)
                .help(isFollowed ? "取消关注" : "关注贴吧")
                .accessibilityIdentifier(isFollowed ? "forum-unfollow" : "forum-follow")
            } else if let readError {
                Button("重试关注状态") { readRequest = UUID() }.help(readError)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("载入关注状态")
            }
        }
        .task(id: readRequest) {
            readError = nil
            do {
                let membership = try await session.api.forumMembership(account: account, forum: forum)
                try Task.checkCancellation()
                guard account.sessionIdentity == session.account?.sessionIdentity else { return }
                isFollowed = session.relationships.forumFollowOverride(accountID: account.id, forum: forum) ?? membership.isFollowed
                session.relationships.seedForumFollow(accountID: account.id, forum: forum, isFollowed: membership.isFollowed)
            } catch {
                if !Task.isCancelled { readError = ReaderErrorMessage.message(for: error) }
            }
        }
        .onReceive(session.relationships.forumFollowDidChange) { change in
            if change.accountID == account.id,
               let confirmed = session.relationships.forumFollowOverride(accountID: account.id, forum: forum) {
                isFollowed = confirmed
            }
        }
    }
}

private struct MacLoginView: View {
    @EnvironmentObject private var session: MacSession
    @Environment(\.dismiss) private var dismiss
    @State private var validationTask: Task<Void, Never>?
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("登录百度账号").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            LoginWebView { cookies in
                validationTask?.cancel()
                validationTask = Task { @MainActor in
                    isValidating = true
                    defer { isValidating = false }
                    do {
                        let account = try await session.api.validateLogin(cookies: cookies)
                        try Task.checkCancellation()
                        try await session.accountStore.save(account)
                        dismiss()
                    } catch is CancellationError {
                    } catch {
                        errorMessage = ReaderErrorMessage.message(for: error)
                    }
                }
            } onError: { errorMessage = ReaderErrorMessage.message(for: $0) }
            .overlay { if isValidating { ProgressView().padding().background(.regularMaterial) } }
        }
        .frame(width: 540, height: 680)
        .onDisappear { validationTask?.cancel() }
    }
}
