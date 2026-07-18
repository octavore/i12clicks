import SwiftUI
import AppKit

/// Attaches to the "main" window so closing it (red button or Cmd-W) asks
/// whether to keep running in the menu bar or quit InternationalClicks entirely.
struct WindowCloseHandler: NSViewRepresentable {
    @EnvironmentObject var store: InstanceStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, store: store)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private var store: InstanceStore?

        func attach(to window: NSWindow?, store: InstanceStore) {
            guard let window, self.window == nil else { return }
            self.window = window
            self.store = store
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let store, !store.instances.isEmpty else { return true }

            let alert = NSAlert()
            alert.messageText = "Keep ClickHouse Running in the Menu Bar?"
            alert.informativeText = "Closing this window leaves your instances available from the menu bar. Choose Quit to stop all running servers and exit completely."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Quit InternationalClicks")

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSApp.terminate(nil)
                return false
            }
            return true
        }
    }
}
