import SwiftUI

private enum ReaderSection: String, CaseIterable, Identifiable {
    case home = "首页", forum = "进吧", search = "搜索"
    var id: Self { self }
    var icon: String {
        switch self {
        case .home: return "house"
        case .forum: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        }
    }
}

/// Search rows identify the matched reply as well as the thread.
private struct MacThreadDestination: Identifiable {
    let thread: ThreadSummary
    var postID: UInt64? = nil
    var id: String { "\(thread.id)-\(postID ?? 0)" }
}

struct MacReaderView: View {
    @EnvironmentObject private var session: MacSession
    @State private var section: ReaderSection? = .home
    @State private var input = ""
    @State private var query = ""
    @State private var selectedThread: String?
    @State private var threads: [MacThreadDestination] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reloadID = UUID()
    @State private var showsLogin = false
    @State private var activeLoadID: UUID?

    var body: some View {
        NavigationSplitView {
            List(ReaderSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("TiebaPure")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Image(systemName: "person.crop.circle")
                    if let account = session.account {
                        Text(account.displayName).lineLimit(1)
                        Spacer()
                        Button("退出") { Task { await session.logOut() } }
                    } else {
                        Button("登录百度账号") { showsLogin = true }
                    }
                }
                .font(.callout)
                .padding()
            }
        } content: {
            VStack(spacing: 0) {
                if section != .home {
                    HStack {
                        TextField(section == .forum ? "贴吧名称" : "搜索帖子", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(submitQuery)
                        Button(section == .forum ? "打开" : "搜索", action: submitQuery)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                    Divider()
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding()
                }
                List(threads, selection: $selectedThread) { destination in
                    let thread = destination.thread
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.title).font(.headline).lineLimit(2)
                        Text(thread.textPreview).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        HStack {
                            Text(thread.forumDisplayNameResolved ?? thread.author.displayNameResolved)
                            Spacer()
                            Label("\(thread.replyCount)", systemImage: "bubble.right")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(destination.id)
                }
                .overlay {
                    if isLoading && threads.isEmpty {
                        ProgressView()
                    } else if threads.isEmpty && errorMessage == nil {
                        ContentUnavailableView(
                            section == .home ? "暂无帖子" : "\(section?.rawValue ?? "搜索")",
                            systemImage: section?.icon ?? "magnifyingglass"
                        )
                    }
                }
                HStack {
                    if isLoading { ProgressView().controlSize(.small) }
                    Spacer()
                    if hasMore {
                        Button("加载更多") { reloadID = UUID() }
                            .disabled(isLoading)
                    }
                }
                .padding(10)
            }
            .navigationTitle(section?.rawValue ?? "首页")
            .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 500)
            .toolbar {
                Button {
                    page = 1
                    reloadID = UUID()
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isLoading)
            }
        } detail: {
            if let destination = threads.first(where: { $0.id == selectedThread }) {
                MacThreadView(thread: destination.thread, initialPostID: destination.postID)
                    .id(destination.id)
            } else {
                ContentUnavailableView("选择一个帖子", systemImage: "text.bubble")
            }
        }
        .onChange(of: section) { _, _ in
            input = ""
            query = ""
            resetList()
        }
        .onChange(of: session.account?.sessionIdentity) { _, _ in resetList() }
        .task(id: reloadID) { await loadThreads() }
        .sheet(isPresented: $showsLogin) { MacLoginView() }
        .alert("账号状态", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if $0 == false { session.errorMessage = nil } }
        )) {
            Button("好") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }

    private func submitQuery() {
        query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        resetList()
    }

    private func resetList() {
        threads = []
        selectedThread = nil
        page = 1
        hasMore = false
        reloadID = UUID()
    }

    @MainActor
    private func loadThreads() async {
        let requestID = UUID()
        activeLoadID = requestID
        errorMessage = nil
        isLoading = false
        guard section == .home || query.isEmpty == false else { return }
        let requestedPage = page
        isLoading = true
        defer { if activeLoadID == requestID { isLoading = false } }
        do {
            let incoming: [MacThreadDestination]
            let more: Bool
            switch section {
            case .home, nil:
                incoming = try await session.api.personalizedThreads(account: session.account, page: requestedPage, loadType: requestedPage == 1 ? 1 : 2)
                    .map { MacThreadDestination(thread: $0) }
                more = incoming.isEmpty == false
            case .forum:
                incoming = try await session.api.forumThreads(account: session.account, forumName: query, page: requestedPage, category: .replyTime)
                    .map { MacThreadDestination(thread: $0) }
                more = incoming.isEmpty == false
            case .search:
                let result = try await session.api.searchThreads(keyword: query, page: requestedPage, sortType: 5, filterType: 2, forumName: nil, pageSize: 30)
                incoming = result.results.map { MacThreadDestination(thread: $0.threadSummary, postID: $0.postID) }
                more = result.hasMore
            }
            try Task.checkCancellation()
            guard activeLoadID == requestID else { return }
            if requestedPage == 1 { threads = [] }
            var ids = Set(threads.map(\.id))
            threads += incoming.filter { ids.insert($0.id).inserted }
            hasMore = more
            page = requestedPage + 1
        } catch is CancellationError {
        } catch {
            guard Task.isCancelled == false, activeLoadID == requestID else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
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
