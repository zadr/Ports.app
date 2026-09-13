import PortsCLI
import SwiftUI

/// Shown when a port has more than one build installed, so a single version can
/// be activated or removed without touching the others.
struct InstalledVersionsSection: View {
    let portName: String

    @Environment(PortsModel.self) private var model

    private var versions: [InstalledPort] {
        model.installed.filter { $0.name == portName }
    }

    var body: some View {
        if versions.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Installed Versions").font(.headline)
                ForEach(versions) { port in
                    HStack(spacing: 8) {
                        Text(specifier(port))
                            .monospaced()
                        if port.isActive {
                            Text("active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !port.isActive {
                            Button("Activate") {
                                model.run(.activate(name: portName, version: specifier(port)))
                            }
                        }
                        Button("Uninstall", role: .destructive) {
                            model.run(.uninstall(name: portName, version: specifier(port)))
                        }
                    }
                }
            }
        }
    }

    private func specifier(_ port: InstalledPort) -> String {
        port.versionString + port.variantSummary
    }
}
