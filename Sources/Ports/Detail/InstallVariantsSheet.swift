import PortsCLI
import SwiftUI

struct InstallVariantsSheet: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var variants: [PortVariant] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if variants.isEmpty {
                    ContentUnavailableView(
                        "No Variants",
                        systemImage: "slider.horizontal.3",
                        description: Text("\(portName) declares no variants.")
                    )
                } else {
                    List(variants) { variant in
                        Toggle(isOn: toggleBinding(for: variant.name)) {
                            VStack(alignment: .leading) {
                                Text(variant.name)
                                if !variant.summary.isEmpty {
                                    Text(variant.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Install \(portName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install") {
                        model.run(.install(name: portName, variants: tokens()))
                        dismiss()
                    }
                }
            }
        }
        .task {
            let loaded = await model.variants(for: portName)
            variants = loaded
            selected = Set(loaded.filter { $0.isSelected }.map { $0.name })
            isLoading = false
        }
    }

    private func toggleBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(name) },
            set: { isOn in
                if isOn { selected.insert(name) } else { selected.remove(name) }
            }
        )
    }

    private func tokens() -> [String] {
        variants.map { selected.contains($0.name) ? "+\($0.name)" : "-\($0.name)" }
    }
}
