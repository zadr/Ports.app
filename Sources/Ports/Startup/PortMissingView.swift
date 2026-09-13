import AppKit
import SwiftUI

struct PortMissingView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("MacPorts Not Found", systemImage: "shippingbox")
        } description: {
            Text("The port command was not found on this system's PATH.")
        } actions: {
            Button("Choose port Binary…") { chooseExecutable() }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the port executable, typically at /opt/local/bin/port."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.useManualExecutable(at: url.path(percentEncoded: false)) }
    }
}
