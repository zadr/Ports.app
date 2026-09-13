import SwiftUI

struct DependentsSection: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @State private var dependents: [String]?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Dependents", isExpanded: $isExpanded) {
            if let dependents {
                if dependents.isEmpty {
                    Text("No installed ports depend on this.").foregroundStyle(.secondary)
                } else {
                    ForEach(dependents, id: \.self) { name in
                        Button(name) { model.selectedPortName = name }
                            .buttonStyle(.link)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded, dependents == nil else { return }
            dependents = await model.dependents(for: portName)
        }
    }
}
