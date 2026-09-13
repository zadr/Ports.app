import PortsCLI
import SwiftUI

struct DependenciesSection: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @State private var dependencies: PortDependencies?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Dependencies", isExpanded: $isExpanded) {
            if let dependencies {
                if dependencies.isEmpty {
                    Text("No dependencies.").foregroundStyle(.secondary)
                } else {
                    group("Library", dependencies.library)
                    group("Build", dependencies.build)
                    group("Runtime", dependencies.runtime)
                    group("Extract", dependencies.extract)
                    group("Fetch", dependencies.fetch)
                    group("Test", dependencies.test)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded, dependencies == nil else { return }
            dependencies = await model.dependencies(for: portName)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ForEach(names, id: \.self) { name in
                    Button(name) { model.selectedPortName = name }
                        .buttonStyle(.link)
                }
            }
        }
    }
}
