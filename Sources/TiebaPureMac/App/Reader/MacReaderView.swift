import SwiftUI

struct MacReaderView: View {
    @Environment(MacSession.self) private var session

    @State private var section: ReaderSection = .home
    @State private var sections = MacReaderWorkspace()
    @State private var showsLogin = false
    @State private var showsProfile = false

    private var state: MacReaderSectionState { sections[section] }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<ReaderSection?>(
                get: { section }, set: { if let value = $0 { show(value) } }
            )) {
                ForEach(ReaderSection.allCases.filter { !$0.requiresAccount }) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                        .accessibilityIdentifier("section-\(item.id)")
                }
                if session.account != nil {
                    Section("账号") {
                        ForEach(ReaderSection.allCases.filter(\.requiresAccount)) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                                .accessibilityIdentifier("section-\(item.id)")
                        }
                    }
                }
            }
            .navigationTitle("TiebaPure-Mac")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom, spacing: 0) { accountBar }
        } detail: {
            MacReaderSectionView(state: state, openFollowedForum: openFollowedForum)
                .id(state.id)
                .overlay(alignment: .top) { MacSessionNotice() }
        }
        .focusedSceneValue(\.macReaderActions, readerActions)
        .onChange(of: session.account?.sessionIdentity) { _, _ in
            sections = MacReaderWorkspace()
            if section.requiresAccount && session.account == nil { section = .home }
        }
        .onReceive(session.forumFollowDidChange) { change in
            if change.accountID == session.account?.id { sections[.followedForums].followed.reload() }
        }
        .onReceive(session.favoriteDidChange) { change in
            guard change.session == session.account?.sessionIdentity else { return }
            sections[.favorites].pages.reload()
            for state in sections.values where state.thread?.thread.id == change.threadID {
                state.thread?.isFavorite = change.isFavorite
            }
        }
        .sheet(isPresented: $showsLogin) { MacLoginView() }
    }

    private var readerActions: MacReaderActions {
        let state = state
        return MacReaderActions(
            show: show,
            find: find,
            reload: state.canReload && (!section.requiresAccount || session.account != nil) ? reload : nil,
            back: state.activeThread == nil ? nil : state.backToList,
            forward: state.canGoForward ? state.forwardToThread : nil,
            searchSort: state.activeThread == nil && (section == .search || (state.isInForum && !state.query.isEmpty)) ? Binding(
                get: { state.searchSort },
                set: { value in
                    guard state.searchSort != value else { return }
                    state.searchSort = value
                    if !state.query.isEmpty {
                        state.discardThread()
                        state.reloadThreads()
                    }
                }
            ) : nil,
            forumSort: state.showsForumTopics ? Binding(
                get: { state.forumSort },
                set: { value in
                    guard let forum = state.forum, state.forumSort != value else { return }
                    session.forumSort.select(value, for: forum)
                    state.forumSort = value
                    state.discardThread()
                    state.reloadThreads()
                }
            ) : nil,
            onlyFeatured: state.showsForumTopics ? Binding(
                get: { state.onlyFeatured },
                set: { value in
                    guard state.onlyFeatured != value else { return }
                    state.onlyFeatured = value
                    state.discardThread()
                    state.reloadThreads()
                }
            ) : nil
        )
    }

    private func reload() {
        if let reading = state.activeThread {
            reading.reloadFromTop()
        } else if section == .followedForums {
            state.followed.reload()
        } else {
            state.pages.reload()
        }
    }

    private var accountBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                MacAccountAvatar(url: session.account?.portraitURL)
                if let account = session.account {
                    Text(account.displayName.isEmpty ? account.name : account.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Menu {
                        Button("个人主页") { showsProfile = true }
                        Button("退出登录", role: .destructive) { Task { [session] in await session.logOut() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(session.isLoggingOut)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("账号菜单")
                    .accessibilityIdentifier("account-menu")
                    .popover(isPresented: $showsProfile, arrowEdge: .top) {
                        MacAccountProfile(account: account)
                            .id(account.sessionIdentity)
                    }
                } else {
                    Button("登录") { showsLogin = true }
                        .accessibilityIdentifier("account-login")
                    Spacer(minLength: 0)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private func show(_ destination: ReaderSection) {
        guard !destination.requiresAccount || session.account != nil else { return }
        section = destination
    }

    private func find() {
        let target = section == .forum ? state : sections[.search]
        target.backToList()
        target.searchFocusRequested = true
        show(target.section)
    }

    private func openFollowedForum(_ forum: Forum) {
        sections[.forum].openForum(forum, sort: session.forumSort.selection(for: forum))
        show(.forum)
    }
}

private struct MacSessionNotice: View {
    @Environment(MacSession.self) private var session

    var body: some View {
        if let message = session.errorMessage {
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.circle")
                Button("关闭提示", systemImage: "xmark") { session.errorMessage = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(10)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
            .padding(12)
        }
    }
}
