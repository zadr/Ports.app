import PortsCLI
import SwiftUI

struct ContentColumnView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        switch model.selectedSection {
        case .installed:
            PortListView(title: "Installed", ports: model.installed)
        case .updates:
            UpdatesListView()
        case .requested:
            PortListView(title: "Requested", ports: model.installed.filter { $0.isRequested })
        case .inactive:
            PortListView(title: "Inactive", ports: model.installed.filter { !$0.isActive })
        case .customized:
            CustomizedListView()
        case .search:
            SearchView()
        case .sources, .configuration, .globalVariants:
            EmptyView()
        }
    }
}
