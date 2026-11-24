import SwiftUI

struct MacThreadRow: View {
    let thread: ThreadSummary
    var forumCategory: ForumThreadCategory? = nil

    var body: some View {
        let preview = thread.textPreview
        let date = switch forumCategory {
        case .replyTime, .featured: thread.lastReplyAt ?? thread.createdAt
        case .publishTime, nil: thread.createdAt ?? thread.lastReplyAt
        }
        let thumbnails = Array(thread.blocks.lazy.compactMap { block -> URL? in
            guard case let .image(image) = block else { return nil }
            return image.thumbnailURL ?? image.originalURL
        }.prefix(3))
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(thread.title).font(.headline).lineLimit(2)
                if !preview.isEmpty {
                    Text(preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 7) {
                    if let forum = thread.forumDisplayNameResolved {
                        Text(forum)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(thread.author.displayNameResolved)
                    HStack(spacing: 7) {
                        if let date {
                            Text("·").accessibilityHidden(true)
                            Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        }
                        Text("·").accessibilityHidden(true)
                        Label("\(thread.replyCount)", systemImage: "bubble.right")
                            .accessibilityLabel("\(thread.replyCount) 条回复")
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !thumbnails.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, url in
                        MacRemoteImage(url: url, maximumPixelSize: 192, contentMode: .fill, placeholder: "photo")
                            .frame(width: 54, height: 54)
                            .background(.quaternary)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }
                .accessibilityLabel("\(thumbnails.count) 张图片缩略图")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
