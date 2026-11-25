import Foundation
import ImageIO

/// Downloads and decodes on the generic executor, outside SwiftUI view isolation.
enum ReaderImageLoader {
    private static let thumbnails = makeCache(mebibytes: 16)
    private static let readingImages = makeCache(mebibytes: 48)

    static func cachedImage(url: URL, maximumPixelSize: Int) -> CGImage? {
        let size = decodeSize(for: maximumPixelSize)
        guard !url.isFileURL, let cache = cache(for: size) else { return nil }
        return cache.object(forKey: "\(size):\(url.absoluteString)" as NSString)
    }

    static func thumbnail(url: URL, maximumPixelSize: Int) async throws -> CGImage {
        let size = decodeSize(for: maximumPixelSize)
#if DEBUG
        if let fixture = ScreenshotThumbnail.image(url: url, maximumPixelSize: size) {
            return fixture
        }
#endif
        let cache = url.isFileURL ? nil : cache(for: size)
        let key = "\(size):\(url.absoluteString)" as NSString
        if let cached = cache?.object(forKey: key) { return cached }

        let (source, _, _) = try await TiebaImageDownloadClient.shared.validatedImage(from: url)
        try Task.checkCancellation()
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ] as CFDictionary) else { throw TiebaImageDownloadError.invalidImageData }
        try Task.checkCancellation()
        cache?.setObject(thumbnail, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return thumbnail
    }

    private static func decodeSize(for requested: Int) -> Int {
        // Avatar and list thumbnail variants share the same small decode.
        (96...192).contains(requested) ? 192 : TiebaImageDecodePolicy.decodeTargetPixelSize(requested)
    }

    private static func cache(for size: Int) -> NSCache<NSString, CGImage>? {
        if size <= 192 { return thumbnails }
        return size <= 1600 ? readingImages : nil
    }

    private static func makeCache(mebibytes: Int) -> NSCache<NSString, CGImage> {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = mebibytes * 1_024 * 1_024
        return cache
    }
}
