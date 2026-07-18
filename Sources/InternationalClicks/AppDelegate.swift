import AppKit

/// Ensures every running ClickHouse instance is stopped before the app
/// actually terminates, regardless of how termination was triggered (Cmd-Q,
/// the "Quit" menu bar item, or choosing "Quit" from the window-close prompt).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: InstanceStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowVisibilityChanged),
            name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowVisibilityChanged),
            name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    /// Only a titled window (the main window or Settings) should keep the app
    /// in the Dock; the menu bar extra itself has no such window.
    @objc private func windowVisibilityChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains {
                $0.isVisible && $0.styleMask.contains(.titled)
            }
            NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, !store.instances.isEmpty else { return .terminateNow }

        Task {
            for instance in store.instances {
                await instance.stopAndWait()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
