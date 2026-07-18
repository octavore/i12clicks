import AppKit
import SwiftUI

/// Ensures every running ClickHouse instance is stopped before the app
/// actually terminates, regardless of how termination was triggered (Cmd-Q,
/// the "Quit" menu bar item, or choosing "Quit" from the window-close prompt).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: InstanceStore?
    var openWindow: OpenWindowAction?

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
        DispatchQueue.main.async { [weak self] in self?.updateActivationPolicy() }
    }

    private func updateActivationPolicy() {
        let hasVisibleWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    /// Reopening the app (e.g. double-clicking it in Finder/Launchpad while
    /// it's already running as a menu-bar-only accessory app) should surface
    /// the main window, since there's no Dock icon to click otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow?(id: "main")
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, !store.instances.isEmpty else { return .terminateNow }

        if KeepRunningPrompt.resolve() == .keepRunning {
            // orderOut (not close()) so this doesn't re-trigger WindowCloseHandler's
            // own "keep running?" prompt on the same window.
            for window in NSApp.windows where window.styleMask.contains(.titled) {
                window.orderOut(nil)
            }
            updateActivationPolicy()
            return .terminateCancel
        }

        Task {
            for instance in store.instances {
                await instance.stopAndWait()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
