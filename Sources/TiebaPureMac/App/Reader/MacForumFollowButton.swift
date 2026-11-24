import SwiftUI

struct MacForumFollowButton: View {
    @EnvironmentObject private var session: MacSession
    let forum: Forum
    let account: Account

    @State private var isFollowed: Bool?
    @State private var readError: String?
    @State private var readRequest = UUID()
    @State private var isWriting = false

    var body: some View {
        Group {
            if let isFollowed {
                Button(isFollowed ? "已关注" : "关注") {
                    isWriting = true
                    Task {
                        defer { isWriting = false }
                        do {
                            self.isFollowed = try await session.setForumFollowed(forum, account: account, followed: !isFollowed)
                        } catch is CancellationError {
                        } catch {
                            if account.sessionIdentity == session.account?.sessionIdentity {
                                session.errorMessage = ReaderErrorMessage.message(for: error)
                            }
                        }
                    }
                }
                .disabled(isWriting || session.isLoggingOut)
                .help(isFollowed ? "取消关注" : "关注贴吧")
                .accessibilityIdentifier(isFollowed ? "forum-unfollow" : "forum-follow")
            } else if let readError {
                Button("重试关注状态") { readRequest = UUID() }.help(readError)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("载入关注状态")
            }
        }
        .task(id: readRequest) {
            readError = nil
            do {
                isFollowed = try await session.forumFollowState(forum, account: account)
            } catch {
                if !Task.isCancelled { readError = ReaderErrorMessage.message(for: error) }
            }
        }
        .onReceive(session.forumFollowDidChange) { change in
            if change.accountID == account.id, SocialRelationshipState.sameForum(change.forum, forum) {
                isFollowed = change.isFollowed
            }
        }
    }
}
