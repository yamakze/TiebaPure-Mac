import SwiftUI

/// Restores the last visible item when the current section creates a new scroll view.
struct ReaderScrollView<ID: Hashable, Content: View>: View {
    @Binding private var position: ID?
    @State private var didRestorePosition = false
    private let contentWidth: CGFloat
    private let content: Content

    init(position: Binding<ID?>, contentWidth: CGFloat = .infinity, @ViewBuilder content: () -> Content) {
        _position = position
        self.contentWidth = contentWidth
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) { content }
                    .frame(maxWidth: contentWidth)
                    .frame(maxWidth: .infinity)
            }
                .scrollPosition(id: Binding(
                    get: { position },
                    set: { if didRestorePosition, let visible = $0 { position = visible } }
                ), anchor: .top)
                .task {
                    guard !didRestorePosition else { return }
                    // Restore explicitly after the targets are mounted. SwiftUI can report the first item
                    // while rebuilding the viewport, before it applies the stored position.
                    if let position { scroll.scrollTo(position, anchor: .top) }
                    didRestorePosition = true
                }
        }
    }
}

/// One outstanding request per list. A reset invalidates results from the old query.
struct ReaderPages<Item: Identifiable> {
    struct Request: Equatable {
        let id = UUID()
        let page: Int
        let replacesItems: Bool
    }

    private enum LoadPhase {
        case notStarted
        case loading(Request)
        case loaded
        case failed(Request, String)
    }

    private(set) var items: [Item] = []
    private var seen: Set<Item.ID> = []
    private var phase = LoadPhase.notStarted
    private(set) var nextPage: Int?

    var request: Request? {
        guard case let .loading(request) = phase else { return nil }
        return request
    }

    var error: String? {
        guard case let .failed(_, message) = phase else { return nil }
        return message
    }

    mutating func loadInitialPage() {
        guard case .notStarted = phase else { return }
        reload()
    }

    mutating func reload(clear: Bool = false) {
        if clear { self = Self() }
        phase = .loading(Request(page: 1, replacesItems: true))
    }

    mutating func loadNext() {
        guard case .loaded = phase, let nextPage else { return }
        phase = .loading(Request(page: nextPage, replacesItems: false))
    }

    mutating func retry() {
        guard case let .failed(failedRequest, _) = phase else { return }
        phase = .loading(Request(page: failedRequest.page, replacesItems: failedRequest.replacesItems))
    }

    mutating func accept(_ incoming: [Item], nextPage: Int?, totalCount: Int? = nil, for request: Request) {
        guard self.request == request else { return }
        if request.replacesItems {
            items = []
            seen = []
        }
        for item in incoming where seen.insert(item.id).inserted {
            items.append(item)
        }
        self.nextPage = totalCount.map { items.count >= $0 } == true ? nil : nextPage
        phase = .loaded
    }

    mutating func fail(_ error: Error, for request: Request) {
        guard self.request == request else { return }
        phase = .failed(request, ReaderErrorMessage.message(for: error))
    }
}

struct ReaderPageFooter: View {
    var loading: Bool
    var error: String?
    var nextPage: Int?
    let loadNext: () -> Void
    let retry: () -> Void

    var body: some View {
        if let error {
            HStack {
                Text(error).foregroundStyle(.secondary)
                Button("重试", action: retry).buttonStyle(.link)
                    .accessibilityIdentifier("reader-retry")
            }
            .font(.callout)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        } else if loading {
            ProgressView().controlSize(.small)
                .accessibilityIdentifier("reader-loading")
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        } else if let nextPage {
            Color.clear.frame(height: 1)
                .accessibilityHidden(true)
                .task(id: nextPage) { loadNext() }
        }
    }
}
