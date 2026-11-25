import SwiftUI

struct MacThreadView: View {
    @Environment(MacSession.self) private var session
    @Bindable var reading: ThreadReadingState
    @State private var imagePreview: MacImagePreviewSelection?

    private var thread: ThreadSummary { reading.thread }

    var body: some View {
        floors
        .navigationTitle(reading.header?.forumDisplayNameResolved ?? thread.forumDisplayNameResolved ?? "帖子")
        .toolbar {
            Toggle("只看楼主", systemImage: "person.crop.circle", isOn: Binding(
                get: { reading.onlyAuthor }, set: reading.setOnlyAuthor
            ))
                .toggleStyle(.button)
                .help("只看楼主")
                .accessibilityIdentifier("only-thread-author")
            if let account = session.account, let isFavorite = reading.isFavorite, let main = reading.pages.items.first {
                Button(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "bookmark.fill" : "bookmark") {
                    reading.isUpdatingFavorite = true
                    // A submitted write remains active when the reader closes this thread.
                    Task { [session, reading, thread] in
                        defer { reading.isUpdatingFavorite = false }
                        do {
                            try await session.setThreadFavorite(
                                account: account, threadID: thread.id, forumID: reading.forumID ?? thread.forumID,
                                postID: reading.targetPostID ?? main.id, isFavorite: !isFavorite
                            )
                        } catch {
                            session.reportMutationFailure(error, account: account)
                        }
                    }
                }
                .help(isFavorite ? "取消收藏" : "收藏")
                .disabled(reading.isUpdatingFavorite || session.isLoggingOut)
                .accessibilityIdentifier(isFavorite ? "thread-unfavorite" : "thread-favorite")
            }
            if let url = URL(string: "https://tieba.baidu.com/p/\(thread.id)") {
                ShareLink(item: url)
            }
        }
        .inspector(isPresented: Binding(
            get: { reading.selectedReply != nil },
            set: { if !$0 { reading.selectedReply = nil } }
        )) {
            if let reply = reading.selectedReply {
                MacSubpostsView(threadID: thread.id, forumID: reading.forumID ?? thread.forumID,
                                reading: reply, close: { reading.selectedReply = nil },
                                preview: { imagePreview = $0 })
                    .id(reply.post.id)
                    .inspectorColumnWidth(min: 260, ideal: 330, max: 440)
            }
        }
        .sheet(item: $imagePreview) { MacImagePreview(selection: $0) }
        .onAppear { reading.pages.loadInitialPage() }
        .task(id: reading.pages.request) { [request = reading.pages.request] in
            if let request { await loadPage(request) }
        }
    }

    private var floors: some View {
        ReaderScrollView(position: $reading.scrollPosition, contentWidth: 812) {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(reading.header?.title ?? thread.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                    .padding(.bottom, 18)
                    .id(ThreadReadingState.ScrollTarget.top)
                let authorID = reading.pages.items.first?.author.id
                ForEach(reading.pages.items) { post in
                    floor(post, authorID: authorID)
                        .id(ThreadReadingState.ScrollTarget.post(post.id))
                }
                ReaderPageFooter(loading: reading.pages.request != nil, error: reading.pages.error,
                                 nextPage: reading.pages.nextPage, loadNext: { reading.pages.loadNext() },
                                 retry: { reading.pages.retry() })
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(24, for: .scrollContent)
        .accessibilityIdentifier("thread-floors")
    }

    private func floor(_ post: Post, authorID: Int64?) -> some View {
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
                    .accessibilityIdentifier("post-floor-\(post.id)")
            }
            MacContentBlocks(blocks: post.blocks) { imagePreview = $0 }
            if post.subpostCount > 0 {
                Button("\(post.subpostCount) 条回复") {
                    reading.selectedReply = SubpostsReadingState(post: post)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("replies-\(post.id)")
            }
            Divider().padding(.top, 4)
        }
        .padding(.top, 15)
    }

    @MainActor
    private func loadPage(_ request: ReaderPages<Post>.Request) async {
        guard reading.pages.request == request else { return }
        let requestedPage = request.page
        let onlyAuthor = reading.onlyAuthor
        let account = session.account
        do {
            if request.replacesItems, let account {
                await session.waitForFavoriteWrite(account: account, threadID: thread.id)
                try Task.checkCancellation()
            }
            let incoming = try await session.api.threadPage(
                account: account, threadID: thread.id, page: requestedPage,
                forumID: reading.forumID ?? thread.forumID, postID: request.replacesItems ? reading.pendingEntryPostID : nil,
                onlyAuthor: onlyAuthor
            )
            try Task.checkCancellation()
            var posts = incoming.posts.filter { $0.floor != 1 }
            if request.replacesItems {
                var mainPost = ThreadPageMainPostPolicy.mainPost(in: incoming)
                if mainPost == nil {
                    let first = try await session.api.threadPage(
                        account: account, threadID: thread.id, page: 1, forumID: incoming.forum.id, onlyAuthor: onlyAuthor
                    )
                    try Task.checkCancellation()
                    mainPost = ThreadPageMainPostPolicy.mainPost(in: first)
                }
                guard let mainPost else { throw TiebaAPIError.missingMainPost }
                posts.insert(mainPost, at: 0)
            }
            guard reading.pages.request == request, account?.sessionIdentity == session.account?.sessionIdentity else { return }
            reading.header = incoming.thread
            reading.forumID = incoming.forum.id
            if request.replacesItems { reading.isFavorite = incoming.isCollected }
            reading.pages.accept(posts, nextPage: incoming.hasMore ? max(requestedPage, incoming.currentPage) + 1 : nil, for: request)
            reading.locateEntryPost(in: posts)
        } catch {
            if !Task.isCancelled { reading.pages.fail(error, for: request) }
        }
    }
}

private struct MacSubpostsView: View {
    @Environment(MacSession.self) private var session
    let threadID: Int64
    let forumID: Int64?
    @Bindable var reading: SubpostsReadingState
    let close: () -> Void
    let preview: (MacImagePreviewSelection) -> Void

    private var post: Post { reading.post }

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
                ReaderScrollView(position: $reading.scrollPosition) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(reading.pages.items) { subpost in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(subpost.author.displayNameResolved).font(.headline)
                                MacContentBlocks(blocks: subpost.blocks, preview: preview)
                                Divider()
                            }
                        }
                        if reading.pages.items.isEmpty && reading.pages.nextPage == nil
                            && reading.pages.request == nil && reading.pages.error == nil {
                            Text("暂无回复").foregroundStyle(.secondary)
                        }
                        ReaderPageFooter(loading: reading.pages.request != nil, error: reading.pages.error, nextPage: reading.pages.nextPage,
                                         loadNext: { reading.pages.loadNext() }, retry: { reading.pages.retry() })
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(14, for: .scrollContent)
                .onAppear { reading.pages.loadInitialPage() }
                .task(id: reading.pages.request) { [request = reading.pages.request] in
                    guard let request, reading.pages.request == request else { return }
                    do {
                        let incoming = try await session.api.subposts(account: session.account, threadID: threadID,
                                                                      postID: post.id, forumID: forumID, page: request.page)
                        try Task.checkCancellation()
                        reading.pages.accept(incoming, nextPage: incoming.isEmpty ? nil : request.page + 1,
                                             totalCount: post.subpostCount, for: request)
                    } catch {
                        if !Task.isCancelled { reading.pages.fail(error, for: request) }
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
    let preview: (MacImagePreviewSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { offset in
                switch blocks[offset] {
                case let .text(text):
                    Text(text).textSelection(.enabled)
                case let .mention(_, text):
                    Text(text).foregroundStyle(.tint).textSelection(.enabled)
                case let .link(title, url):
                    if let url { Link(title.isEmpty ? url.absoluteString : title, destination: url) }
                    else { Text(title).textSelection(.enabled) }
                case let .emoticon(code):
                    if let name = TiebaEmoticon.imageName(for: code), let url = TiebaEmoticon.remoteImageURL(imageName: name) {
                        MacRemoteImage(url: url, maximumPixelSize: 64).frame(width: 28, height: 28)
                    } else { Text(TiebaEmoticon.displayText(for: code)) }
                case let .image(image):
                    if let url = image.thumbnailURL ?? image.originalURL {
                        let hasDimensions = image.width > 0 && image.height > 0
                        // Missing dimensions use a 4:3 preview so decoding cannot move the following content.
                        let ratio = hasDimensions ? CGFloat(image.aspectRatio) : 4.0 / 3
                        let width = hasDimensions ? CGFloat(image.width) : 480
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(maxWidth: min(width, 812, 480 * ratio))
                            .overlay {
                                MacRemoteImage(url: url, preview: (image.originalURL ?? url, { thumbnail in
                                    var images: [MacPreviewImage] = []
                                    var selectedIndex = 0
                                    for (index, block) in blocks.enumerated() {
                                        guard case let .image(content) = block,
                                              let source = MacPreviewImage(content) else { continue }
                                        if index == offset { selectedIndex = images.count }
                                        images.append(source)
                                    }
                                    preview(MacImagePreviewSelection(images: images, index: selectedIndex, thumbnail: thumbnail))
                                }))
                                .accessibilityIdentifier("post-image-\(offset)")
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
