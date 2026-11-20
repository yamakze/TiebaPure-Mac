import SwiftUI

struct MacThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        let preview = thread.textPreview
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
                        Text("·").accessibilityHidden(true)
                    }
                    Text(thread.author.displayNameResolved).lineLimit(1)
                    if let createdAt = thread.createdAt {
                        Text("·").accessibilityHidden(true)
                        Text(createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .fixedSize()
                    }
                    Text("·").accessibilityHidden(true)
                    Label("\(thread.replyCount)", systemImage: "bubble.right")
                        .accessibilityLabel("\(thread.replyCount) 条回复")
                        .fixedSize()
                }
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
