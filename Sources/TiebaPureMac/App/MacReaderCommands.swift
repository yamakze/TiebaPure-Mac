import AppKit
import SwiftUI

enum ReaderSection: String, CaseIterable, Identifiable {
    case home = "首页", forum = "进吧", search = "搜索"
    case followedForums = "关注的吧", favorites = "收藏夹"

    var id: Self { self }
    var requiresAccount: Bool { self == .followedForums || self == .favorites }

    var icon: String {
        switch self {
        case .home: "house"
        case .forum: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .followedForums: "star"
        case .favorites: "bookmark"
        }
    }
}

enum ReaderSearchSort: Int, CaseIterable {
    case latest = 5
    case relevance = 2

    var title: String {
        switch self {
        case .latest: "最新"
        case .relevance: "相关"
        }
    }
}

struct MacReaderActions {
    let show: (ReaderSection) -> Void
    let find: () -> Void
    let reload: (() -> Void)?
    let back: (() -> Void)?
    let forward: (() -> Void)?
    let searchSort: Binding<ReaderSearchSort>?
    let forumSort: Binding<ForumThreadCategory>?
    let onlyFeatured: Binding<Bool>?
}

extension FocusedValues {
    @Entry var macReaderActions: MacReaderActions?
}

struct MacReaderCommands: Commands {
    @FocusedValue(\.macReaderActions) private var actions
    @Binding var appearance: AppAppearance

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("刷新") { actions?.reload?() }
                .keyboardShortcut("r")
                .disabled(actions?.reload == nil)
            Divider()
            Button("首页") { actions?.show(.home) }.keyboardShortcut("1")
                .disabled(actions == nil)
            Button("进吧") { actions?.show(.forum) }.keyboardShortcut("2")
                .disabled(actions == nil)
            Button("搜索") { actions?.show(.search) }.keyboardShortcut("3")
                .disabled(actions == nil)
            Divider()
            Button("返回") { actions?.back?() }.keyboardShortcut("[")
                .disabled(actions?.back == nil)
            Button("前进") { actions?.forward?() }.keyboardShortcut("]")
                .disabled(actions?.forward == nil)
            Divider()
            if let sort = actions?.searchSort {
                Menu("搜索结果排序") {
                    ForEach(ReaderSearchSort.allCases, id: \.self) { option in
                        Button { sort.wrappedValue = option } label: {
                            if sort.wrappedValue == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                        .keyboardShortcut(option == .latest ? "1" : "2", modifiers: [.command, .option])
                    }
                }
            }
            if let sort = actions?.forumSort, let onlyFeatured = actions?.onlyFeatured {
                Menu("吧内主题排序") {
                    ForEach(ForumThreadCategory.latestSortOptions) { option in
                        Button { sort.wrappedValue = option } label: {
                            if sort.wrappedValue == option { Label(option.sortOptionTitle, systemImage: "checkmark") }
                            else { Text(option.sortOptionTitle) }
                        }
                        .disabled(onlyFeatured.wrappedValue)
                        .keyboardShortcut(option == .replyTime ? "1" : "2", modifiers: [.command, .option])
                    }
                    Divider()
                    Toggle("只看精华", isOn: onlyFeatured)
                        .keyboardShortcut("3", modifiers: [.command, .option])
                }
            }
            Menu("外观") {
                Picker("外观", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
        CommandGroup(after: .textEditing) {
            Button("搜索帖子") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .help) {
            if let url = Self.projectURL {
                Button("项目主页") { NSWorkspace.shared.open(url) }
                Button("发布记录") { NSWorkspace.shared.open(url.appending(path: "releases")) }
            }
        }
    }

    static let projectURL = URL(string: "https://github.com/yamakze/TiebaPure-Mac")
}
