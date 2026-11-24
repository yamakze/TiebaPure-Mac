import SwiftUI

struct MacPreviewImage {
    let fullSizeURL: URL
    let thumbnailURL: URL?

    init?(_ content: ImageContent) {
        guard let fullSizeURL = content.originalURL ?? content.thumbnailURL else { return nil }
        self.fullSizeURL = fullSizeURL
        thumbnailURL = content.thumbnailURL
    }
}

struct MacImagePreviewSelection: Identifiable {
    let id = UUID()
    let images: [MacPreviewImage]
    let index: Int
    let thumbnail: CGImage?
}

struct MacImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let selection: MacImagePreviewSelection
    @State private var index: Int
    @State private var zoom: CGFloat = 1

    init(selection: MacImagePreviewSelection) {
        self.selection = selection
        _index = State(initialValue: selection.index)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("图片预览").font(.headline)
                Spacer()
                if selection.images.count > 1 {
                    Button("上一张", systemImage: "chevron.left") { select(index - 1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(index == 0)
                        .accessibilityIdentifier("image-preview-previous")
                    Text("\(index + 1) / \(selection.images.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("image-preview-position")
                    Button("下一张", systemImage: "chevron.right") { select(index + 1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(index + 1 == selection.images.count)
                        .accessibilityIdentifier("image-preview-next")
                    Divider().frame(height: 16)
                }
                Button("缩小", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom / 1.5) }
                    .disabled(zoom <= 1)
                Button("适合窗口", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { zoom = 1 }
                    .disabled(zoom == 1)
                Button("放大", systemImage: "plus.magnifyingglass") { zoom = min(5, zoom * 1.5) }
                    .disabled(zoom >= 5)
                    .accessibilityIdentifier("image-preview-zoom-in")
                Divider().frame(height: 16)
                Button("关闭图片预览", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("image-preview-close")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(14)
            Divider()
            MacImagePreviewPage(source: selection.images[index], zoom: $zoom,
                                thumbnail: index == selection.index ? selection.thumbnail : nil)
                .id(index)
        }
        .frame(minWidth: 640, idealWidth: 820, minHeight: 420, idealHeight: 570)
    }

    private func select(_ next: Int) {
        index = next
        zoom = 1
    }
}

private struct MacImagePreviewPage: View {
    let source: MacPreviewImage
    @Binding var zoom: CGFloat
    @State private var thumbnail: CGImage?
    @State private var fullSizeImage: CGImage?
    @State private var thumbnailUnavailable = false
    @State private var failed = false
    @State private var retry = 0

    init(source: MacPreviewImage, zoom: Binding<CGFloat>, thumbnail: CGImage?) {
        self.source = source
        _zoom = zoom
        _thumbnail = State(initialValue: thumbnail)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .underPageBackgroundColor)
            if let image = fullSizeImage ?? thumbnail {
                MacZoomableImage(image: image, zoom: $zoom)
            }
            if failed {
                HStack(spacing: 8) {
                    Label(thumbnail == nil ? "无法载入图片" : "无法载入大图",
                          systemImage: "exclamationmark.triangle")
                    Button("重试") {
                        failed = false
                        retry += 1
                    }
                    .accessibilityIdentifier("image-preview-retry")
                }
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            } else if fullSizeImage == nil {
                if thumbnailUnavailable {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在加载大图")
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
                    .padding(12)
            }
        }
        .task {
            // Only a separate thumbnail can arrive ahead of the full-size request.
            guard thumbnail == nil, let url = source.thumbnailURL, url != source.fullSizeURL else { return }
            do {
                let image = try await ReaderImageLoader.thumbnail(url: url, maximumPixelSize: 1600)
                try Task.checkCancellation()
                if fullSizeImage == nil { thumbnail = image }
            } catch {
                if !Task.isCancelled { thumbnailUnavailable = true }
            }
        }
        .task(id: retry) {
            do {
                let loaded = try await ReaderImageLoader.thumbnail(url: source.fullSizeURL, maximumPixelSize: 4096)
                try Task.checkCancellation()
                fullSizeImage = loaded
                thumbnail = nil
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct MacZoomableImage: View {
    let image: CGImage
    @Binding var zoom: CGFloat
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            let fit = min(size.width / imageWidth, size.height / imageHeight)
            let scale = min(5, max(1, zoom * magnification))
            let width = imageWidth * fit * scale
            let height = imageHeight * fit * scale
            let limit = CGSize(width: max(0, (width - size.width) / 2), height: max(0, (height - size.height) / 2))
            let position = clamped(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), to: limit)

            Image(image, scale: 1, label: Text("帖子图片"))
                .resizable()
                .frame(width: width, height: height)
                .position(x: size.width / 2 + position.width, y: size.height / 2 + position.height)
                .accessibilityIdentifier("image-preview-display")
                .gesture(
                    DragGesture()
                        .updating($drag) { value, drag, _ in drag = value.translation }
                        .onEnded { value in
                            offset = clamped(CGSize(width: offset.width + value.translation.width,
                                                    height: offset.height + value.translation.height), to: limit)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($magnification) { value, zoom, _ in zoom = value.magnification }
                        .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) }
                )
                .onChange(of: limit) { _, limit in offset = clamped(offset, to: limit) }
        }
        .clipped()
    }

    private func clamped(_ offset: CGSize, to limit: CGSize) -> CGSize {
        CGSize(width: min(limit.width, max(-limit.width, offset.width)),
               height: min(limit.height, max(-limit.height, offset.height)))
    }
}
