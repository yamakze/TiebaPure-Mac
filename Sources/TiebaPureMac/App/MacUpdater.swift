import Combine
import Sparkle
import SwiftUI

@MainActor
final class MacUpdater: ObservableObject {
    @Published private(set) var unavailableReason: String? = "此构建未配置自动更新"
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
            unavailableReason = nil
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
            controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloadsUpdates)
        } catch {
            unavailableReason = error.localizedDescription
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecking(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }
}

struct MacUpdateCommands: Commands {
    @ObservedObject var updater: MacUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查更新…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

struct MacUpdateSettings: View {
    @ObservedObject var updater: MacUpdater

    var body: some View {
        Section("软件更新") {
            if let reason = updater.unavailableReason {
                Text(reason).foregroundStyle(.secondary)
            } else {
                Toggle("自动检查更新", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: updater.setAutomaticChecking
                ))
                Toggle("自动下载并安装更新", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: updater.setAutomaticDownloads
                ))
                .disabled(!updater.automaticallyChecksForUpdates)
            }
        }
    }
}
