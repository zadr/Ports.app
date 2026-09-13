import SwiftUI

struct DetailColumnView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        switch model.selectedSection {
        case .sources:
            SourcesEditorView()
        case .configuration:
            ConfigurationEditorView()
        case .globalVariants:
            GlobalVariantsEditorView()
        default:
            if let name = model.selectedPortName {
                PortDetailView(portName: name)
                    .id(name)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "shippingbox",
                    description: Text("Select a port to see its details.")
                )
            }
        }
    }
}
