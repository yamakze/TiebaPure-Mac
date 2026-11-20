import SwiftUI

@main
struct TiebaPureMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var applicationDelegate
    @StateObject private var session = MacSession()
    @StateObject private var appearance = AppAppearanceStore.live()

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(get: { appearance.selection }, set: { appearance.select($0) })
    }

    var body: some Scene {
        WindowGroup("TiebaPure-Mac", id: "reader") {
            Group {
                if session.isReady {
                    MacReaderView(recentForums: session.recentForums, searchHistory: session.searchHistory)
                }
                else { ProgressView() }
            }
                .environmentObject(session)
                .preferredColorScheme(appearance.selection.preferredColorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .task { await session.load() }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            MacReaderCommands(appearance: selectedAppearance)
            MacUpdateCommands(updater: applicationDelegate.updater)
        }
        Settings {
            Form {
                Picker("外观", selection: selectedAppearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建")
                if let url = MacReaderCommands.projectURL {
                    Link("源码与上游声明", destination: url)
                }
                MacUpdateSettings(updater: applicationDelegate.updater)
            }
            .padding(24)
            .preferredColorScheme(appearance.selection.preferredColorScheme)
            .frame(width: 420)
        }
    }
}
