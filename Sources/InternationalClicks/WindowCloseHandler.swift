import AppKit
import SwiftUI

/// User preference for what happens when closing the main window or quitting
/// while instances are running: ask every time, or always do one or the other.
enum QuitBehavior: String, CaseIterable, Identifiable {
    case ask
    case alwaysKeepRunning
    case alwaysQuit

    static let defaultsKey = "quitBehavior"

    /// Non-View access point (AppDelegate and the window's NSWindowDelegate
    /// aren't SwiftUI views, so they can't use @AppStorage). Settings reads
    /// and writes the same UserDefaults key via @AppStorage.
    static var current: QuitBehavior {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(QuitBehavior.init) ?? .ask
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ask: "Always Ask"
        case .alwaysKeepRunning: "Always Keep Running"
        case .alwaysQuit: "Always Quit"
        }
    }
}

/// Asks whether to keep running in the menu bar or quit InternationalClicks
/// entirely. Shared by closing the main window (red button or Cmd-W) and by
/// quitting the app (Cmd-Q, the menu bar "Quit" item) while instances are running.
enum KeepRunningPrompt {
    enum Choice {
        case keepRunning
        case quit
    }

    @MainActor
    static func resolve() -> Choice {
        switch QuitBehavior.current {
        case .alwaysKeepRunning: return .keepRunning
        case .alwaysQuit: return .quit
        case .ask: return show()
        }
    }

    @MainActor
    private static func show() -> Choice {
        let alert = NSAlert()
        alert.messageText = "Keep ClickHouse running in the menu bar?"
        alert.informativeText =
            "Closing this window leaves your instances available from the menu bar. Choose Quit to stop all running servers and exit completely."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Entirely")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remember this choice"

        let choice: Choice = alert.runModal() == .alertSecondButtonReturn ? .quit : .keepRunning
        if alert.suppressionButton?.state == .on {
            QuitBehavior.current = choice == .quit ? .alwaysQuit : .alwaysKeepRunning
        }
        return choice
    }
}

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

            switch KeepRunningPrompt.resolve() {
            case .keepRunning:
                return true
            case .quit:
                NSApp.terminate(nil)
                return false
            }
        }
    }
}
