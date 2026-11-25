import AppKit
import SwiftUI

@main
struct TiebaPureMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var applicationDelegate
    @State private var session: MacSession
    @StateObject private var appearance = AppAppearanceStore.live()

    init() {
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 1
        let size = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        _session = State(initialValue: MacSession(requestBuilder: .live(
            screenScale: scale,
            screenWidth: Int(size.width * scale),
            screenHeight: Int(size.height * scale)
        )))
    }

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(get: { appearance.selection }, set: { appearance.select($0) })
    }

    var body: some Scene {
        WindowGroup("TiebaPure-Mac", id: "reader") {
            Group {
                if session.isReady {
                    MacReaderView()
                }
                else { ProgressView() }
            }
                .environment(session)
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
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        LabeledContent("版本", value: version)
                    }
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
