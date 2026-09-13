import SwiftUI

@main
struct PortsApp: App {
    @State private var model = PortsModel()

    var body: some Scene {
        Window("Ports", id: "main") {
            RootView()
                .environment(model)
        }
        .windowResizability(.automatic)
    }
}
