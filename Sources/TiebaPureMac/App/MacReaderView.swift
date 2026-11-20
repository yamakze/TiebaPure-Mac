import SwiftUI

private struct MacThreadDestination: Identifiable, Hashable {
    let thread: ThreadSummary
    var postID: UInt64? = nil
    var id: String { "\(thread.id)-\(postID ?? 0)" }

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
    @State private var searchPresented = false
    @State private var searchFocusRequest: UUID?
    @State private var path: [MacThreadDestination] = []
    @State private var forwardDestination: MacThreadDestination?
    @State private var pages = ReaderPages<MacThreadDestination>()
    @State private var threadReload = UUID()
    @State private var showsLogin = false
    @State private var showsProfile = false
    @State private var historyError: String?

    var body: some View {
        NavigationSplitView {
            List(ReaderSection.allCases, selection: Binding<ReaderSection?>(
                get: { section }, set: { if let value = $0 { show(value) } }
            )) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
                    .accessibilityIdentifier("section-\(item.id)")
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
                    case .home:
                        threadList
                    case .forum, .search:
                        threadList
                            .searchable(text: $input, isPresented: $searchPresented, placement: .toolbar,
                                        prompt: section == .forum ? Text("贴吧名称") : Text("搜索帖子"))
                            .task(id: searchFocusRequest) {
                                guard section == .search, path.isEmpty, searchFocusRequest != nil else { return }
                                searchFocusRequest = nil
                                searchPresented = true
                            }
                            .onSubmit(of: .search) { submit(input) }
                            .onExitCommand {
                                if input.isEmpty { searchPresented = false }
                                else { input = "" }
                            }
                            .searchSuggestions {
                                if section == .search && (query.isEmpty || input != query) {
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
                .navigationTitle(section == .forum && !query.isEmpty ? forumTitle : section.rawValue)
                .navigationDestination(for: MacThreadDestination.self) { destination in
                    MacThreadView(thread: destination.thread, initialPostID: destination.postID, reloadID: threadReload)
                }
            }
        }
        .focusedSceneValue(\.macReaderActions, MacReaderActions(
            show: show,
            find: {
                show(.search)
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
            } : nil
        ))
        .onChange(of: session.account?.sessionIdentity) { _, _ in
            path = []
            forwardDestination = nil
            if canReload { pages.reload(clear: true) }
        }
        .task(id: pages.request) { [request = pages.request] in
            if let request { await loadThreads(request) }
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

    private var canReload: Bool { section == .home || !query.isEmpty }

    private var forumTitle: String {
        pages.items.first?.thread.forumDisplayNameResolved ?? query
    }

    private var threadList: some View {
        let prefetchID = pages.items.dropLast(2).last?.id
        return Group {
            if !canReload {
                history
            } else if pages.items.isEmpty && pages.nextPage == nil {
                if pages.request != nil || pages.error != nil {
                    ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: nil,
                                     loadNext: {}, retry: { pages.retry() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(section == .search ? "没有搜索结果" : "暂无帖子",
                                           systemImage: section.icon)
                }
            } else {
                List {
                    ForEach(pages.items) { destination in
                        NavigationLink(value: destination) {
                            MacThreadRow(thread: destination.thread)
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        .accessibilityIdentifier("thread-\(destination.id)")
                        .onAppear {
                            if destination.id == prefetchID { pages.loadNext() }
                        }
                    }
                    if pages.request != nil || pages.error != nil || pages.nextPage != nil {
                        ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: pages.nextPage,
                                         loadNext: { pages.loadNext() }, retry: { pages.retry() })
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let historyError {
                Text(historyError).font(.callout).foregroundStyle(.secondary).padding(8)
            }
        }
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
                                Button { submit(forum.name) } label: {
                                    Label(forum.displayName, systemImage: "number")
                                        .lineLimit(1)
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
                            Button { submit(keyword) } label: { Label(keyword, systemImage: "clock") }
                                .buttonStyle(.plain)
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
        guard section != destination else { return }
        section = destination
        input = ""
        query = ""
        searchPresented = false
        searchFocusRequest = nil
        path = []
        forwardDestination = nil
        historyError = nil
        pages = ReaderPages()
        if destination == .home { pages.reload() }
    }

    private func submit(_ text: String) {
        let value = section == .search ? SearchHistoryPolicy.normalizedKeyword(text)
            : text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func reload() {
        if path.isEmpty { pages.reload() }
        else { threadReload = UUID() }
    }

    @MainActor
    private func loadThreads(_ request: ReaderPages<MacThreadDestination>.Request) async {
        guard pages.request == request else { return }
        let page = request.page
        let section = section
        let query = query
        do {
            let incoming: [MacThreadDestination]
            let next: Int?
            switch section {
            case .home:
                incoming = try await session.api.personalizedThreads(account: session.account, page: page, loadType: page == 1 ? 1 : 2)
                    .map { MacThreadDestination(thread: $0) }
                next = incoming.isEmpty ? nil : page + 1
            case .forum:
                incoming = try await session.api.forumThreads(account: session.account, forumName: query, page: page, category: .replyTime)
                    .map { MacThreadDestination(thread: $0) }
                next = incoming.isEmpty ? nil : page + 1
            case .search:
                let result = try await session.api.searchThreads(keyword: query, page: page)
                incoming = result.results.map { MacThreadDestination(thread: $0.threadSummary, postID: $0.postID) }
                next = result.hasMore ? max(page, result.currentPage) + 1 : nil
            }
            try Task.checkCancellation()
            guard pages.request == request else { return }
            pages.accept(incoming, nextPage: next, for: request)
            if section == .forum, request.replacesItems {
                let forum = incoming.first?.thread.forumRoute
                if !(forum.map { recentForums.save($0) } ?? recentForums.save(name: query,
                    displayName: query.hasSuffix("吧") ? query : "\(query)吧")) {
                    historyError = "无法保存访问记录。"
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            pages.fail(error, for: request)
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
