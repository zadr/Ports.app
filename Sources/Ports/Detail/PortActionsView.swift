import PortsCLI
import PortsOverlay
import SwiftUI

struct PortActionsView: View {
    let portName: String
    let installedPort: InstalledPort?
    let isOutdated: Bool
    let existingFork: PortfileFork?

    @Environment(PortsModel.self) private var model
    @State private var isChoosingVariants = false

    private var installedCount: Int {
        model.installed.count { $0.name == portName }
    }

    var body: some View {
        HStack(spacing: 8) {
            if installedPort == nil {
                Button("Install…") { isChoosingVariants = true }
            } else {
                if isOutdated {
                    Button("Upgrade") { model.run(.upgrade(names: [portName])) }
                }
                if installedPort?.isActive == true {
                    Button("Deactivate") { model.run(.deactivate(name: portName)) }
                } else {
                    Button("Activate") { model.run(.activate(name: portName, version: nil)) }
                }
                Button("Clean") { model.run(.clean(name: portName)) }
                Button(installedCount > 1 ? "Uninstall All" : "Uninstall", role: .destructive) {
                    model.run(.uninstall(name: portName, version: nil))
                }
            }
            Spacer()
            Button(existingFork == nil ? "Edit Portfile" : "Open Portfile") {
                Task { await model.openPortfileEditor(for: portName) }
            }
        }
        .sheet(isPresented: $isChoosingVariants) {
            InstallVariantsSheet(portName: portName)
        }
    }
}
