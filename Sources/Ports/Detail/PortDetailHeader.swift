import PortsCLI
import SwiftUI

struct PortDetailHeader: View {
    let portName: String
    let info: PortInfo?
    let installedPort: InstalledPort?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(portName).font(.title2).bold()
                if let info {
                    Text(info.versionString)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospaced()
                } else if let installedPort {
                    Text(installedPort.versionString)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            if let info, !info.categories.isEmpty {
                Text(info.categories.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let info, !info.homepage.isEmpty, let url = URL(string: info.homepage) {
                Link(info.homepage, destination: url)
                    .font(.caption)
            }
            installStateLabel
        }
    }

    @ViewBuilder
    private var installStateLabel: some View {
        if let installedPort {
            Label(
                installedPort.isActive ? "Installed" : "Installed, Inactive",
                systemImage: installedPort.isActive ? "checkmark.circle.fill" : "moon.zzz"
            )
            .font(.caption)
            .foregroundStyle(installedPort.isActive ? .green : .secondary)
        } else {
            Label("Not Installed", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
