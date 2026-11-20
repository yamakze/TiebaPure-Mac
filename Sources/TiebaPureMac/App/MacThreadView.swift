import SwiftUI

struct MacThreadView: View {
    @EnvironmentObject private var session: MacSession
    let thread: ThreadSummary
    let reloadID: UUID

    @State private var header: ThreadSummary?
    @State private var forumID: Int64?
    @State private var pages = ReaderPages<Post>()
    @State private var selectedPost: Post?
    @State private var onlyAuthor = false
    @State private var targetPostID: UInt64?

    init(thread: ThreadSummary, initialPostID: UInt64?, reloadID: UUID) {
        self.thread = thread
        self.reloadID = reloadID
        _targetPostID = State(initialValue: initialPostID)
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(header?.title ?? thread.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                        .padding(.bottom, 18)
                        .id("thread-top")
                    let authorID = pages.items.first?.author.id
                    ForEach(pages.items) { post in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 8) {
                                Text(post.author.displayNameResolved)
                                    .font(.headline)
                                    .lineLimit(1)
                                if post.floor == 1 || (post.author.id > 0 && post.author.id == authorID) {
                                    Text("楼主")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .fixedSize()
                                }
                                Spacer()
                                if let createdAt = post.createdAt {
                                    Text(createdAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                                        .help(createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(post.floor) 楼")
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            MacContentBlocks(blocks: post.blocks)
                            if post.subpostCount > 0 {
                                Button("\(post.subpostCount) 条回复") { selectedPost = post }
                                .buttonStyle(.link)
                                .accessibilityIdentifier("replies-\(post.id)")
                            }
                        }
                        .padding(.vertical, 15)
                        .id(post.id)
                        Divider()
                    }
                    ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: pages.nextPage,
                                     loadNext: { pages.loadNext() }, retry: { pages.retry() })
                }
                .padding(24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: pages.items.first?.id) { old, new in
                if old == nil, new != nil, let targetPostID,
                   pages.items.contains(where: { $0.id == targetPostID }) {
                    scroll.scrollTo(targetPostID, anchor: .top)
                }
            }
            .onChange(of: onlyAuthor) { _, _ in
                targetPostID = nil
                selectedPost = nil
                scroll.scrollTo("thread-top", anchor: .top)
                pages.reload(clear: true)
            }
            .onChange(of: reloadID) { _, _ in
                selectedPost = nil
                scroll.scrollTo("thread-top", anchor: .top)
                pages.reload()
            }
        }
        .navigationTitle(header?.forumDisplayNameResolved ?? thread.forumDisplayNameResolved ?? "帖子")
        .toolbar {
            Toggle("只看楼主", systemImage: "person.crop.circle", isOn: $onlyAuthor)
                .toggleStyle(.button)
                .help("只看楼主")
                .accessibilityIdentifier("only-thread-author")
            if let url = URL(string: "https://tieba.baidu.com/p/\(thread.id)") {
                ShareLink(item: url)
            }
        }
        .inspector(isPresented: Binding(
            get: { selectedPost != nil },
            set: { if !$0 { selectedPost = nil } }
        )) {
            if let selectedPost {
                MacSubpostsView(threadID: thread.id, forumID: forumID ?? thread.forumID, post: selectedPost) {
                    self.selectedPost = nil
                }
                .id(selectedPost.id)
                .inspectorColumnWidth(min: 260, ideal: 330, max: 440)
            }
        }
        .onAppear {
            if pages.items.isEmpty && pages.request == nil && pages.error == nil { pages.reload() }
        }
        .task(id: pages.request) { [request = pages.request] in
            if let request { await loadPage(request) }
        }
    }

    @MainActor
    private func loadPage(_ request: ReaderPages<Post>.Request) async {
        guard pages.request == request else { return }
        let requestedPage = request.page
        let onlyAuthor = onlyAuthor
        let account = session.account
        do {
            let incoming = try await session.api.threadPage(
                account: account, threadID: thread.id, page: requestedPage,
                forumID: forumID ?? thread.forumID, postID: request.replacesItems && !onlyAuthor ? targetPostID : nil,
                seeLz: onlyAuthor
            )
            try Task.checkCancellation()
            var posts = incoming.posts.filter { $0.floor != 1 }
            if request.replacesItems {
                var mainPost = ThreadPageMainPostPolicy.mainPost(in: incoming)
                if mainPost == nil {
                    let first = try await session.api.threadPage(
                        account: account, threadID: thread.id, page: 1, forumID: incoming.forum.id, seeLz: onlyAuthor
                    )
                    try Task.checkCancellation()
                    mainPost = ThreadPageMainPostPolicy.mainPost(in: first)
                }
                guard let mainPost else { throw TiebaAPIError.missingMainPost }
                posts.insert(mainPost, at: 0)
            }
            guard pages.request == request, account?.sessionIdentity == session.account?.sessionIdentity else { return }
            header = incoming.thread
            forumID = incoming.forum.id
            pages.accept(posts, nextPage: incoming.hasMore ? max(requestedPage, incoming.currentPage) + 1 : nil, for: request)
        } catch {
            if !Task.isCancelled { pages.fail(error, for: request) }
        }
    }
}

private struct MacSubpostsView: View {
    @EnvironmentObject private var session: MacSession
    let threadID: Int64
    let forumID: Int64?
    let post: Post
    let close: () -> Void

    @State private var pages = ReaderPages<Subpost>()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(post.floor) 楼的回复").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("关闭楼中楼")
                    .accessibilityIdentifier("close-subposts")
            }
            .padding(14)
            Divider()
            if let forumID, forumID > 0 {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(pages.items) { subpost in
                            Text(subpost.author.displayNameResolved).font(.headline)
                            MacContentBlocks(blocks: subpost.blocks)
                            Divider()
                        }
                        if pages.items.isEmpty && pages.request == nil && pages.error == nil {
                            Text("暂无回复").foregroundStyle(.secondary)
                        }
                        ReaderPageFooter(loading: pages.request != nil, error: pages.error, nextPage: pages.nextPage,
                                         loadNext: { pages.loadNext() }, retry: { pages.retry() })
                    }
                    .padding(14)
                }
                .onAppear { if pages.items.isEmpty && pages.request == nil && pages.error == nil { pages.reload() } }
                .task(id: pages.request) { [request = pages.request] in
                    guard let request, pages.request == request else { return }
                    do {
                        let incoming = try await session.api.subposts(account: session.account, threadID: threadID,
                                                                      postID: post.id, forumID: forumID, page: request.page)
                        try Task.checkCancellation()
                        let count = Set(pages.items.map(\.id)).union(incoming.map(\.id)).count
                        pages.accept(incoming, nextPage: !incoming.isEmpty && count < post.subpostCount ? request.page + 1 : nil,
                                     for: request)
                    } catch {
                        if !Task.isCancelled { pages.fail(error, for: request) }
                    }
                }
            } else {
                ContentUnavailableView("暂时无法载入回复", systemImage: "exclamationmark.bubble")
            }
        }
        .onExitCommand(perform: close)
    }
}

struct MacContentBlocks: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(text):
                    Text(text).textSelection(.enabled)
                case let .mention(_, text):
                    Text(text).foregroundStyle(.tint).textSelection(.enabled)
                case let .link(title, url):
                    if let url { Link(title.isEmpty ? url.absoluteString : title, destination: url) }
                    else { Text(title).textSelection(.enabled) }
                case let .emoticon(code):
                    if let name = TiebaEmoticon.imageName(for: code), let url = TiebaEmoticon.remoteImageURL(imageName: name) {
                        MacRemoteImage(url: url).frame(width: 28, height: 28)
                    } else { Text(TiebaEmoticon.displayText(for: code)) }
                case let .image(image):
                    if let url = image.originalURL ?? image.thumbnailURL {
                        let hasDimensions = image.width > 0 && image.height > 0
                        // Missing dimensions use a 4:3 preview so decoding cannot move the following content.
                        let ratio = hasDimensions ? CGFloat(image.width) / CGFloat(image.height) : 4.0 / 3
                        let width = hasDimensions ? CGFloat(image.width) : 480
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(maxWidth: min(width, 812, 480 * ratio))
                            .overlay {
                                MacRemoteImage(url: url)
                            }
                            .clipShape(.rect(cornerRadius: 6))
                    }
                case let .video(video):
                    if let url = video.videoURL ?? video.webURL {
                        Link("播放视频", destination: url)
                    } else { Text("视频地址不可用").foregroundStyle(.secondary) }
                case let .voice(voice):
                    if let url = VoiceAudioURLPolicy.url(forMD5: voice.md5) {
                        Link("播放语音", destination: url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
