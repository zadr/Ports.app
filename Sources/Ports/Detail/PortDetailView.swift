import PortsCLI
import SwiftUI

struct PortDetailView: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @State private var info: PortInfo?
    @State private var isLoadingInfo = false

    private var installedPort: InstalledPort? {
        model.installed.first { $0.name == portName && $0.isActive }
            ?? model.installed.first { $0.name == portName }
    }

    private var isOutdated: Bool {
        model.outdated.contains { $0.name == portName }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PortDetailHeader(portName: portName, info: info, installedPort: installedPort)

                if isLoadingInfo && info == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let info {
                    if !info.summary.isEmpty {
                        Text(info.summary)
                    }
                    if !info.details.isEmpty && info.details != info.summary {
                        Text(info.details).foregroundStyle(.secondary)
                    }
                }

                PortActionsView(
                    portName: portName,
                    installedPort: installedPort,
                    isOutdated: isOutdated,
                    existingFork: model.existingFork(for: portName)
                )

                InstalledVersionsSection(portName: portName)

                Divider()

                DependenciesSection(portName: portName)
                DependentsSection(portName: portName)
                if installedPort != nil {
                    InstalledFilesSection(portName: portName)
                    DiskUsageSection(portName: portName)
                }
            }
            .padding()
        }
        .navigationTitle(portName)
        .task(id: portName) {
            isLoadingInfo = true
            info = await model.info(for: portName)
            isLoadingInfo = false
        }
    }
}
