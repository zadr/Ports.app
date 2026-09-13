import PortsCLI
import SwiftUI

struct PortRow: View {
    let port: InstalledPort
    var isOutdated = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(port.name)
                if !port.variantSummary.isEmpty {
                    Text(port.variantSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            Spacer()
            Text(port.versionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
            badges
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if !port.isActive {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.secondary)
                    .help("Inactive")
            }
            if isOutdated {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .help("Update available")
            }
            if port.isRequested {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help("Requested")
            }
        }
    }
}
