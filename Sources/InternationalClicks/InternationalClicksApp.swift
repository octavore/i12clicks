import SwiftUI

@main
struct InternationalClicksApp: App {
    @StateObject private var store = InstanceStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private static let menuBarIcon: NSImage = {
        let url = Bundle.module.url(forResource: "clickhouse", withExtension: "svg")!
        let image = NSImage(contentsOf: url)!
        let ratio = image.size.height / image.size.width
        image.size.height = 14
        image.size.width = 14 / ratio
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(store)
        } label: {
            // For first time users without instances, always open the app at launch,
            // The status item's label is created immediately at launch so
            // we do the check here.
            Image(nsImage: Self.menuBarIcon)
                .onAppear {
                    if store.instances.isEmpty {
                        openWindow(id: "main")
                    }
                }
        }
        .menuBarExtraStyle(.menu)

        Window("ClickHouse", id: "main") {
            MainWindowView()
                .environmentObject(store)
                .onAppear { appDelegate.store = store }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
