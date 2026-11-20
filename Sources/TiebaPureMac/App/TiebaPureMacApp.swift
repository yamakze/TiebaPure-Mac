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
                Section("外观") {
                    Picker("颜色模式", selection: selectedAppearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("settings-appearance")
                }
                MacUpdateSettings(updater: applicationDelegate.updater)
                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建")
                    if let url = MacReaderCommands.projectURL {
                        LabeledContent("项目") {
                            Link("源码与上游声明", destination: url)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            .preferredColorScheme(appearance.selection.preferredColorScheme)
            .frame(width: 460, height: 330)
        }
    }
}
