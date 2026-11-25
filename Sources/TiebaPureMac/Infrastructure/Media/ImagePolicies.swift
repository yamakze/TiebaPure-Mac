import Foundation
import ImageIO

enum TiebaImageRequestPolicy {
    static let maximumRetryCount = 2

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            timeoutInterval: 20
        )
        request.setValue("tieba/12.52.1.0 skin/default", forHTTPHeaderField: "User-Agent")
        request.setValue("https://tieba.baidu.com/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    static func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        guard attempt < maximumRetryCount else { return false }
        return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    static func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maximumRetryCount else { return false }
        let code = (error as? URLError)?.code
        return code == .timedOut
            || code == .networkConnectionLost
            || code == .notConnectedToInternet
            || code == .cannotConnectToHost
            || code == .cannotFindHost
    }

    static func retryDelayNanoseconds(after attempt: Int) -> UInt64 {
        UInt64(250_000_000 * max(attempt + 1, 1))
    }
}

enum TiebaImageSourcePolicy {
    private static let syntheticFailureHost = "fixture.invalid"
#if DEBUG
    private static let syntheticSuccessHost = "fixture-success.invalid"
    static let syntheticOriginalByteCount = 3_670_016
#endif

    static func urls(primary: URL?, fallback: URL? = nil) -> [URL] {
        var result: [URL] = []
        for candidate in [primary, fallback].compactMap({ $0 }) {
            let safeURL: URL
            if SavedThreadMediaAuthorization.shared.allows(candidate) {
                safeURL = candidate
            } else if let validated = TiebaURL.image(candidate.absoluteString) {
                safeURL = validated
            } else {
                continue
            }
            guard result.contains(safeURL) == false else { continue }
            result.append(safeURL)
        }
        return result
    }

    /// UI-test fixtures use this reserved host to exercise the accessible
    /// failure and retry states without consulting DNS or the network stack.
    static func isSyntheticFailureURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == syntheticFailureHost
    }

#if DEBUG
    /// Deterministic UI-test images are generated in memory and never consult
    /// DNS or the network stack.
    static func isSyntheticSuccessURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == syntheticSuccessHost
    }
#endif
}

enum TiebaImageDecodePolicy {
    static let maximumSourceDimension = 32_768
    static let maximumSourcePixels = 100_000_000
    static let maximumDecodedPixelSize = 4_096
    static let maximumPreviewDecodedPixelSize = 2_560
    static let maximumPreviewDisplayScale: CGFloat = 3
    private static let previewDecodeBuckets = [
        128, 256, 384, 512, 640, 768, 1_024, 1_280,
        1_536, 1_792, 2_048, 2_304, 2_560
    ]

    static func allows(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maximumSourceDimension,
              height <= maximumSourceDimension else {
            return false
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow == false && pixels <= maximumSourcePixels
    }

    /// Decode targets are a downscale hint only: they never raise the global
    /// pixel ceiling, and non-positive requests fall back to it.
    static func decodeTargetPixelSize(_ requested: Int) -> Int {
        guard requested > 0 else { return maximumDecodedPixelSize }
        return min(requested, maximumDecodedPixelSize)
    }

    static func previewTargetPixelSize(
        for pointSize: CGSize,
        displayScale: CGFloat
    ) -> Int {
        let longestPointEdge = max(pointSize.width, pointSize.height)
        guard longestPointEdge.isFinite,
              longestPointEdge > 0,
              displayScale.isFinite,
              displayScale > 0 else {
            return 512
        }
        let previewScale = min(displayScale, maximumPreviewDisplayScale)
        let requiredPixels = Int(ceil(longestPointEdge * previewScale))
        return previewDecodeBuckets.first(where: { $0 >= requiredPixels })
            ?? maximumPreviewDecodedPixelSize
    }
}

enum TiebaAnimatedImageDecodePolicy {
    static let maximumFrameCount = 120
    static let maximumDecodedPixels = 24_000_000
    static let defaultFrameDuration = 0.1
    static let minimumFrameDuration = 0.02
    static let maximumFrameDuration = 10.0

    static func frameDuration(properties: [CFString: Any]) -> TimeInterval {
        guard let gifProperties = properties[kCGImagePropertyGIFDictionary]
                as? [CFString: Any] else {
            return defaultFrameDuration
        }
        let rawDuration = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime]
            as? NSNumber)?.doubleValue
            ?? (gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            ?? defaultFrameDuration
        guard rawDuration.isFinite else { return defaultFrameDuration }
        return min(max(rawDuration, minimumFrameDuration), maximumFrameDuration)
    }
}
