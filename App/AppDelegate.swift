import AppKit

/// Prevents the app from quitting when all windows are closed.
/// Required for menu-bar-only agents: closing the tester window must
/// not terminate the process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
