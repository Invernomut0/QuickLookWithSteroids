import AppKit
import OmniPreviewCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Silently refresh the cached Gumroad validation if it's stale.
        LicenseManager.shared.revalidateIfNeeded()
    }
}
