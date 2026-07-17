import SwiftUI

struct MainWindowView: View {
    var body: some View {
        TabView {
            InstanceView()
                .tabItem { Label("Instance", systemImage: "server.rack") }

            QueryWindowView()
                .tabItem { Label("Query", systemImage: "terminal") }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}
