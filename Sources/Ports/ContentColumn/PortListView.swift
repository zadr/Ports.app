import PortsCLI
import SwiftUI

/// Shared list for Installed, Requested and Inactive. `.searchable` filters
/// the given list in place; it does not query the network.
struct PortListView: View {
    let title: String
    let ports: [InstalledPort]

    @Environment(PortsModel.self) private var model
    @State private var query = ""

    private var filtered: [InstalledPort] {
        guard !query.isEmpty else { return ports }
        return ports.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        List(filtered, selection: $model.selectedPortName) { port in
            PortRow(port: port, isOutdated: model.outdated.contains { $0.name == port.name })
                .tag(port.name)
        }
        .searchable(text: $query)
        .navigationTitle(title)
    }
}
