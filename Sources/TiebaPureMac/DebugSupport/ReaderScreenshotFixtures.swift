#if DEBUG
import Foundation
import CoreGraphics

/// Keeps the screenshot run separate from the reader's history and account data.
@MainActor
final class ScreenshotHistory<Entry> {
    let capability = PersistenceCapability.durable
    private var entries: [Entry] = []

    func load() throws -> [Entry] { entries }

    func replaceAll(_ entries: [Entry], beforeCommit: () throws -> Void) throws {
        try beforeCommit()
        self.entries = entries
    }
}

extension ScreenshotHistory: RecentForumPersistence where Entry == RecentForum {}
extension ScreenshotHistory: SearchHistoryPersistence where Entry == String {}

struct ScreenshotSessionCleaner: SessionArtifactCleaning {
    func clear() async throws {}
}

enum ScreenshotThumbnail {
    static func image(url: URL, maximumPixelSize: Int) -> CGImage? {
        guard url.host == "fixture-success.invalid",
              ProcessInfo.processInfo.arguments.contains("SCREENSHOT_FIXTURES") else { return nil }
        let size = min(maximumPixelSize, 220)
        guard let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let index = url.lastPathComponent.utf8.reduce(0) { $0 + Int($1) } % 3
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.23, 0.54, 0.68), (0.40, 0.53, 0.40), (0.70, 0.43, 0.32)]
        let (red, green, blue) = colors[index]
        canvas.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        let edge = CGFloat(size)
        canvas.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        canvas.setFillColor(red: 1, green: 0.92, blue: 0.75, alpha: 1)
        canvas.fillEllipse(in: CGRect(x: edge * 0.63, y: edge * 0.60, width: edge * 0.18, height: edge * 0.18))
        canvas.setFillColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
        canvas.move(to: .zero)
        canvas.addLine(to: CGPoint(x: edge * 0.37, y: edge * 0.62))
        canvas.addLine(to: CGPoint(x: edge * 0.73, y: edge * 0.18))
        canvas.addLine(to: CGPoint(x: edge, y: edge * 0.48))
        canvas.addLine(to: CGPoint(x: edge, y: 0))
        canvas.closePath()
        canvas.fillPath()
        return canvas.makeImage()
    }
}
#endif
