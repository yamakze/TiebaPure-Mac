import SwiftUI

/// One outstanding request per list. A reset invalidates results from the old query.
struct ReaderPages<Item: Identifiable> {
    struct Request: Equatable {
        let id = UUID()
        let page: Int
        let replacesItems: Bool
    }

    private(set) var items: [Item] = []
    private var seen: Set<Item.ID> = []
    private(set) var request: Request?
    private(set) var error: String?
    private var failedRequest: Request?
    private(set) var nextPage: Int?

    mutating func reload(clear: Bool = false) {
        if clear { self = Self() }
        error = nil
        failedRequest = nil
        request = Request(page: 1, replacesItems: true)
    }

    mutating func loadNext() {
        guard request == nil, error == nil, let nextPage else { return }
        request = Request(page: nextPage, replacesItems: false)
    }

    mutating func retry() {
        guard let failedRequest else { return }
        error = nil
        self.failedRequest = nil
        request = Request(page: failedRequest.page, replacesItems: failedRequest.replacesItems)
    }

    mutating func accept(_ incoming: [Item], nextPage: Int?, for request: Request) {
        guard self.request == request else { return }
        if request.replacesItems {
            items = []
            seen = []
        }
        items += incoming.filter { seen.insert($0.id).inserted }
        self.nextPage = nextPage
        self.request = nil
    }

    mutating func fail(_ error: Error, for request: Request) {
        guard self.request == request else { return }
        self.error = ReaderErrorMessage.message(for: error)
        failedRequest = request
        self.request = nil
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
