import SwiftUI

@main
struct ClickHouseApp: App {
    @StateObject private var store = InstanceStore()

    var body: some Scene {
        MenuBarExtra("ClickHouse", systemImage: "cylinder.split.1x2") {
            StatusMenuView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("ClickHouse", id: "main") {
            MainWindowView()
                .environmentObject(store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
