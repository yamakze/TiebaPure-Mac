import SwiftUI
import ImageIO

struct MacRemoteImage: View {
    let url: URL
    var maximumPixelSize = 1600
    var contentMode: ContentMode = .fit
    var placeholder: String?
    var preview: (shareURL: URL, open: (NSImage?) -> Void)?

    private static let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
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
                image = try await Self.load(url: url, maximumPixelSize: maximumPixelSize)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
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

    static func load(url: URL, maximumPixelSize: Int) async throws -> NSImage {
        let thumbnail = try await thumbnail(url: url, maximumPixelSize: maximumPixelSize)
        try Task.checkCancellation()
        return NSImage(cgImage: thumbnail, size: .zero)
    }

    private static func thumbnail(url: URL, maximumPixelSize: Int) async throws -> CGImage {
#if DEBUG
        if let fixture = ScreenshotThumbnail.image(url: url, maximumPixelSize: maximumPixelSize) {
            return fixture
        }
#endif
        let cacheKey: NSString? = maximumPixelSize <= 192 && !url.isFileURL
            ? "\(maximumPixelSize):\(url.absoluteString)" as NSString
            : nil
        if let cacheKey, let cached = thumbnails.object(forKey: cacheKey) { return cached }
        let payload = try await TiebaImageDownloadClient.shared.download(from: url)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary) else { throw TiebaImageDownloadError.invalidImageData }
        if let cacheKey {
            thumbnails.setObject(thumbnail, forKey: cacheKey, cost: thumbnail.bytesPerRow * thumbnail.height)
        }
        return thumbnail
    }
}
