import SwiftUI

/// Raw-text mode shared by the configuration editor. Re-instantiate with a
/// new `.id()` when the underlying file text changes externally, so the
/// initializer can reseed `editedText`.
struct RawConfigEditor: View {
    let path: String
    let onSave: (String) async -> Void

    @State private var editedText: String
    private let originalText: String

    init(path: String, text: String, onSave: @escaping (String) async -> Void) {
        self.path = path
        self.onSave = onSave
        self.originalText = text
        self._editedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            TextEditor(text: $editedText)
                .monospaced()
                .padding(4)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert") { editedText = originalText }
                    .disabled(editedText == originalText)
                Button("Save") { Task { await onSave(editedText) } }
                    .disabled(editedText == originalText)
            }
        }
    }
}
