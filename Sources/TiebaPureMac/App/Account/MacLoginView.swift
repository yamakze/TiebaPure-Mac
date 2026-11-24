import SwiftUI

struct MacLoginView: View {
    private struct Failure {
        let message: String
        let needsFreshWebSession: Bool
    }

    @EnvironmentObject private var session: MacSession
    @Environment(\.dismiss) private var dismiss
    @State private var validationTask: Task<Void, Never>?
    @State private var failure: Failure?
    @State private var webSessionID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("登录百度账号").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            if let failure {
                HStack {
                    Text(failure.message).foregroundStyle(.red)
                    if failure.needsFreshWebSession {
                        Button("重新登录") {
                            self.failure = nil
                            webSessionID = UUID()
                        }
                    }
                }
                .padding()
            }
            LoginWebView { cookies in
                guard validationTask == nil else { return }
                validationTask = Task { @MainActor in
                    failure = nil
                    defer { validationTask = nil }
                    do {
                        try await session.signIn(cookies: cookies)
                    } catch is CancellationError {
                    } catch {
                        failure = Failure(message: ReaderErrorMessage.message(for: error), needsFreshWebSession: true)
                    }
                }
            } onError: {
                failure = Failure(message: ReaderErrorMessage.message(for: $0), needsFreshWebSession: false)
            }
            .id(webSessionID)
            .overlay { if validationTask != nil { ProgressView().padding().background(.regularMaterial) } }
        }
        .frame(width: 540, height: 680)
        .onChange(of: session.account?.sessionIdentity) { _, identity in
            if identity != nil { dismiss() }
        }
        .onDisappear { validationTask?.cancel() }
    }
}
