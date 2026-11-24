import Foundation
import ImageIO

/// Downloads and decodes on the generic executor, outside SwiftUI view isolation.
enum ReaderImageLoader {
    private static let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    static func thumbnail(url: URL, maximumPixelSize: Int) async throws -> CGImage {
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
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary) else { throw TiebaImageDownloadError.invalidImageData }
        try Task.checkCancellation()
        if let cacheKey {
            thumbnails.setObject(thumbnail, forKey: cacheKey, cost: thumbnail.bytesPerRow * thumbnail.height)
        }
        return thumbnail
    }
}
