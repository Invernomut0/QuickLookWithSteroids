import AppKit
import OmniPreviewCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Close the tester window that SwiftUI opens automatically at launch.
        // The user can reopen it from the menu bar.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue == "tester" || window.title == "Preview Tester" {
                window.close()
            }
        }

        // Silently refresh the cached Gumroad validation if it's stale.
        LicenseManager.shared.revalidateIfNeeded()
    }
}
