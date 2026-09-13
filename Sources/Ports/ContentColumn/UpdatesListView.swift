import PortsCLI
import SwiftUI

struct UpdatesListView: View {
    @Environment(PortsModel.self) private var model
    @State private var query = ""

    private var filtered: [OutdatedPort] {
        guard !query.isEmpty else { return model.outdated }
        return model.outdated.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        List(filtered, selection: $model.selectedPortName) { port in
            UpdateRow(port: port)
                .tag(port.name)
        }
        .searchable(text: $query)
        .navigationTitle("Updates")
        .toolbar {
            ToolbarItem {
                Button("Upgrade All") { model.run(.upgradeOutdated) }
                    .disabled(model.outdated.isEmpty)
            }
        }
    }
}

private struct UpdateRow: View {
    @Environment(PortsModel.self) private var model
    let port: OutdatedPort

    var body: some View {
        HStack {
            Text(port.name)
            Spacer()
            Text(port.installedVersion)
                .monospaced()
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(port.availableVersion)
                .monospaced()
            if let note = port.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Upgrade") { model.run(.upgrade(names: [port.name])) }
        }
    }
}
