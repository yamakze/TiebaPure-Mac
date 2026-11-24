import SwiftUI
import CoreGraphics

struct MacRemoteImage: View {
    let url: URL
    var maximumPixelSize = 1600
    var contentMode: ContentMode = .fit
    var placeholder: String?
    var preview: (shareURL: URL, open: (CGImage?) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let preview {
                Button { preview.open(image) } label: {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看图片")
                .help("查看图片")
                .contextMenu {
                    Button("查看图片") { preview.open(image) }
                    ShareLink(item: preview.shareURL) { Text("分享图片链接") }
                }
            } else {
                content
                    .contextMenu {
                        if image != nil, placeholder == nil {
                            ShareLink(item: url) { Text("分享图片链接") }
                        }
                    }
            }
        }
        .animation(reduceMotion || placeholder != nil ? nil : .easeInOut(duration: 0.18), value: image != nil)
        .task(id: url) {
            image = nil
            failed = false
            do {
                let loaded = try await ReaderImageLoader.thumbnail(url: url, maximumPixelSize: maximumPixelSize)
                try Task.checkCancellation()
                image = loaded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
        } else if let placeholder {
            Image(systemName: placeholder)
                .resizable().scaledToFit().padding(4)
                .foregroundStyle(.secondary)
                .accessibilityLabel(failed ? "图片加载失败" : "正在加载图片")
        } else if failed {
            Label("图片加载失败", systemImage: "photo.badge.exclamationmark")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}
