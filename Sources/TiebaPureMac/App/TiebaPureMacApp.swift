import SwiftUI

@main
struct TiebaPureMacApp: App {
    @StateObject private var session = MacSession()
    @StateObject private var appearance = AppAppearanceStore.live()

    var body: some Scene {
        WindowGroup("TiebaPure", id: "reader") {
            Group {
                if session.isReady { MacReaderView() }
                else { ProgressView() }
            }
                .environmentObject(session)
                .preferredColorScheme(appearance.selection.preferredColorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .task { await session.load() }
        }
        .defaultSize(width: 1180, height: 800)
        Settings {
            Form {
                Picker("外观", selection: Binding(
                    get: { appearance.selection }, set: { appearance.select($0) }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建")
                if let url = URL(string: "https://github.com/yamakze/TiebaPure-Mac") {
                    Link("源码与上游声明", destination: url)
                }
            }
            .padding(24)
            .preferredColorScheme(appearance.selection.preferredColorScheme)
            .frame(width: 420)
        }
    }
}
