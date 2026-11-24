import SwiftUI

struct MacAccountAvatar: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                MacRemoteImage(url: url, maximumPixelSize: 128, contentMode: .fill, placeholder: "person.crop.circle.fill")
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct MacAccountProfile: View {
    @EnvironmentObject private var session: MacSession
    let account: Account
    @State private var profile: UserProfile?
    @State private var error: String?
    @State private var reloadID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MacAccountAvatar(url: account.portraitURL)
                Text(profile?.user.displayNameResolved ?? account.displayName).font(.headline)
            }
            if let profile {
                if !profile.intro.isEmpty { Text(profile.intro).textSelection(.enabled) }
                LabeledContent("关注", value: profile.followingCount.formatted())
                LabeledContent("粉丝", value: profile.followerCount.formatted())
                LabeledContent("帖子", value: profile.threadCount.formatted())
            } else if let error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { reloadID = UUID() }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .task(id: reloadID) {
            error = nil
            guard let id = Int64(account.uid), id > 0 else {
                error = "账号资料不可用。"
                return
            }
            do {
                let user = UserSummary(id: id, name: account.name, displayName: account.displayName, portrait: account.portrait)
                let result = try await session.api.userProfile(account: account, user: user)
                try Task.checkCancellation()
                profile = result
            } catch {
                if !Task.isCancelled { self.error = ReaderErrorMessage.message(for: error) }
            }
        }
    }
}
