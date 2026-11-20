import AppKit

@MainActor
final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    let updater = MacUpdater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the bundle icon for the running application as well as for Finder.
        if let resource = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.url(forResource: resource, withExtension: nil),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
        updater.start()
    }
}
