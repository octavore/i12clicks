import SwiftUI

@main
struct ClickHouseApp: App {
    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra("ClickHouse", systemImage: "cylinder.split.1x2") {
            StatusMenuView()
                .environmentObject(server)
        }
        .menuBarExtraStyle(.window)

        Window("ClickHouse Query", id: "query") {
            QueryWindowView()
                .environmentObject(server)
        }
    }
}
