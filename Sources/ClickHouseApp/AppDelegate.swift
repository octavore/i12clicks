import AppKit

/// Ensures every running ClickHouse instance is stopped before the app
/// actually terminates, regardless of how termination was triggered (Cmd-Q,
/// the "Quit" menu bar item, or choosing "Quit" from the window-close prompt).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: InstanceStore?

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
