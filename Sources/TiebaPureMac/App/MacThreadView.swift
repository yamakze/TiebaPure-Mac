import SwiftUI
import ImageIO

struct MacThreadView: View {
    @EnvironmentObject private var session: MacSession
    let thread: ThreadSummary
    var initialPostID: UInt64? = nil
    @State private var threadPage: ThreadPage?
    @State private var page = 1
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var selectedPost: Post?
    @State private var reloadID = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text(threadPage?.thread.title ?? thread.title).font(.title2.bold()).textSelection(.enabled)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("重试") { reloadID = UUID() }
                }
                if let threadPage {
                    if let mainPost = ThreadPageMainPostPolicy.mainPost(in: threadPage) {
                        postView(mainPost)
                        Divider()
                    }
                    ForEach(threadPage.posts.filter { $0.floor != 1 }) { post in
                        postView(post)
                        Divider()
                    }
                    HStack {
                        Button("上一页") {
                            page = threadPage.currentPage - 1
                            reloadID = UUID()
                        }.disabled(threadPage.currentPage <= 1 || isLoading)
                        Spacer()
                        Text("第 \(threadPage.currentPage) / \(threadPage.totalPage) 页").foregroundStyle(.secondary)
                        Spacer()
                        Button("下一页") {
                            page = threadPage.currentPage + 1
                            reloadID = UUID()
                        }.disabled(threadPage.hasMore == false || isLoading)
                    }
                }
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(thread.forumDisplayNameResolved ?? "帖子")
        .toolbar {
            if let url = URL(string: "https://tieba.baidu.com/p/\(thread.id)") {
                ShareLink(item: url)
            }
        }
        .task(id: reloadID) { await loadPage() }
        .sheet(item: $selectedPost) { post in
            MacSubpostsView(threadID: thread.id, forumID: threadPage?.forum.id ?? thread.forumID, post: post)
        }
    }

    private func postView(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(post.author.displayNameResolved).font(.headline)
                Spacer()
                Text("\(post.floor) 楼").foregroundStyle(.secondary)
            }
            MacContentBlocks(blocks: post.blocks)
            if post.subpostCount > 0 {
                Button("\(post.subpostCount) 条回复") { selectedPost = post }.buttonStyle(.link)
            }
        }
    }

    @MainActor
    private func loadPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var incoming = try await session.api.threadPage(account: session.account, threadID: thread.id, page: page, forumID: thread.forumID, postID: threadPage == nil ? initialPostID : nil)
            try Task.checkCancellation()
            if ThreadPageMainPostPolicy.mainPost(in: incoming) == nil && threadPage?.mainPost == nil {
                let recovered = try await session.api.threadPage(account: session.account, threadID: thread.id, page: 1, forumID: incoming.forum.id)
                try Task.checkCancellation()
                incoming = ThreadPageMainPostPolicy.merging(incoming, previousMainPost: ThreadPageMainPostPolicy.mainPost(in: recovered), requestedPage: page)
            }
            incoming = ThreadPageMainPostPolicy.merging(incoming, previousMainPost: threadPage?.mainPost, requestedPage: page)
            guard ThreadPageMainPostPolicy.mainPost(in: incoming) != nil else {
                throw TiebaAPIError.missingMainPost
            }
            threadPage = incoming
            page = incoming.currentPage
        } catch is CancellationError {
        } catch {
            guard Task.isCancelled == false else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
    }
}

private struct MacSubpostsView: View {
    @EnvironmentObject private var session: MacSession
    @Environment(\.dismiss) private var dismiss
    let threadID: Int64
    let forumID: Int64?
    let post: Post
    @State private var subposts: [Subpost] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var errorMessage: String?
    @State private var reloadID = UUID()

    var body: some View {
        VStack {
            HStack {
                Text("\(post.floor) 楼的回复").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            List(subposts) { subpost in
                VStack(alignment: .leading, spacing: 8) {
                    Text(subpost.author.displayNameResolved).font(.headline)
                    MacContentBlocks(blocks: subpost.blocks)
                }.padding(.vertical, 8)
            }
            if isLoading { ProgressView() }
            if hasMore || errorMessage != nil {
                Button(errorMessage == nil ? "加载更多" : "重试") { reloadID = UUID() }.disabled(isLoading)
            }
        }
        .padding(.bottom)
        .frame(width: 620, height: 540)
        .task(id: reloadID) {
            guard let forumID, forumID > 0 else {
                errorMessage = "缺少贴吧 ID，无法加载回复。"
                return
            }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                let incoming = try await session.api.subposts(account: session.account, threadID: threadID, postID: post.id, forumID: forumID, page: page)
                try Task.checkCancellation()
                var ids = Set(subposts.map(\.id))
                subposts += incoming.filter { ids.insert($0.id).inserted }
                hasMore = incoming.isEmpty == false && subposts.count < post.subpostCount
                page += 1
            } catch is CancellationError {
            } catch {
                guard Task.isCancelled == false else { return }
                errorMessage = ReaderErrorMessage.message(for: error)
            }
        }
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
                        MacRemoteImage(url: url).frame(maxHeight: 480)
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

private struct MacRemoteImage: View {
    let url: URL
    @State private var image: NSImage?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .contextMenu {
                        ShareLink(item: url) { Text("分享图片链接") }
                    }
            } else if let errorMessage {
                Label(errorMessage, systemImage: "photo.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            } else { ProgressView().controlSize(.small) }
        }
        .task(id: url) {
            do {
                let payload = try await TiebaImageDownloadClient.shared.download(from: url)
                let decoded = try await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1600
                          ] as CFDictionary) else { throw TiebaImageDownloadError.invalidImageData }
                    return NSImage(cgImage: thumbnail, size: .zero)
                }.value
                try Task.checkCancellation()
                image = decoded
            } catch is CancellationError {
            } catch { errorMessage = "图片加载失败" }
        }
    }
}
