import PortsConfig
import SwiftUI

struct GlobalVariantsEditorView: View {
    @Environment(PortsModel.self) private var model
    @State private var variants: [String] = []
    @State private var newVariant = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(variants, id: \.self) { variant in
                    HStack {
                        Text(variant).monospaced()
                        Spacer()
                        Button(role: .destructive) { remove(variant) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            HStack {
                TextField("+name or -name", text: $newVariant)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                Button("Add") { add() }
                    .disabled(!isValidToken(newVariant))
            }
            .padding(8)
        }
        .navigationTitle("Global Variants")
        .task(id: model.variantsConfiguration?.variants) {
            variants = model.variantsConfiguration?.variants ?? []
        }
    }

    private func isValidToken(_ token: String) -> Bool {
        (token.hasPrefix("+") || token.hasPrefix("-")) && token.count > 1
    }

    private func add() {
        variants.append(newVariant)
        newVariant = ""
        persist()
    }

    private func remove(_ variant: String) {
        variants.removeAll { $0 == variant }
        persist()
    }

    private func persist() {
        guard let configuration = model.variantsConfiguration else { return }
        let text = configuration.applying(variants)
        Task {
            do {
                try await configuration.save(text)
                model.loadConfigurations()
            } catch {
                model.banner = BannerError(error)
            }
        }
    }
}
