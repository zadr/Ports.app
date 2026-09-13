import PortsCLI
import SwiftUI

struct EnvironmentStatusView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        if model.environment?.requiresAdministrator == true {
            Label("Operations require administrator approval", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}
