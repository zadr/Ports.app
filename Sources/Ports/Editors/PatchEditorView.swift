import PortsOverlay
import SwiftUI

struct PatchEditorView: View {
    let path: String

    @Environment(PortsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var originalText = ""

    private var hasChanges: Bool { text != originalText }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .monospaced()
                .padding(4)
                .navigationTitle(URL(filePath: path).lastPathComponent)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Revert") { text = originalText }
                            .disabled(!hasChanges)
                        Button("Save") { Task { await save() } }
                            .disabled(!hasChanges)
                    }
                }
        }
        .frame(minWidth: 560, minHeight: 400)
        .task { load() }
    }

    private func load() {
        guard let overlayManager = model.overlayManager else { return }
        do {
            let loaded = try overlayManager.patchText(path)
            text = loaded
            originalText = loaded
        } catch {
            model.banner = BannerError(error)
        }
    }

    private func save() async {
        guard let overlayManager = model.overlayManager else { return }
        do {
            try await overlayManager.writePatch(text, to: path)
            originalText = text
        } catch {
            model.banner = BannerError(error)
        }
    }
}
