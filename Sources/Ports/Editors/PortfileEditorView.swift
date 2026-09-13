import PortsOverlay
import SwiftUI

struct PortfileEditorView: View {
    let fork: PortfileFork

    @Environment(PortsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var originalText = ""
    @State private var showDiff = false
    @State private var diffText = ""
    @State private var patches: [String] = []
    @State private var selectedPatch: String?

    private var hasChanges: Bool { text != originalText }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                statusBar
                if showDiff {
                    ScrollView {
                        Text(diffText.isEmpty ? "No differences from upstream." : diffText)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    TextEditor(text: $text)
                        .monospaced()
                        .padding(4)
                }
                if !patches.isEmpty {
                    Divider()
                    List(patches, id: \.self, selection: $selectedPatch) { path in
                        Text(URL(filePath: path).lastPathComponent).tag(path)
                    }
                    .frame(height: 120)
                }
            }
            .navigationTitle("\(fork.category)/\(fork.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("Diff", isOn: $showDiff)
                        .toggleStyle(.button)
                    Button("Revert", role: .destructive) { Task { await revert() } }
                    Button("Remove Fork", role: .destructive) { Task { await removeFork() } }
                    Button("Save") { Task { await save() } }
                        .disabled(!hasChanges)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { load() }
        .task(id: showDiff) {
            guard showDiff else { return }
            await loadDiff()
        }
        .sheet(isPresented: Binding(
            get: { selectedPatch != nil },
            set: { if !$0 { selectedPatch = nil } }
        )) {
            if let selectedPatch {
                PatchEditorView(path: selectedPatch)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text("Saving reindexes the tree.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if fork.upstreamChanged {
                Label("Upstream changed since this fork was made", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(8)
    }

    private func load() {
        guard let overlayManager = model.overlayManager else { return }
        do {
            let loaded = try overlayManager.portfileText(fork)
            text = loaded
            originalText = loaded
            patches = try overlayManager.patchFiles(fork)
        } catch {
            model.banner = BannerError(error)
        }
    }

    private func loadDiff() async {
        guard let overlayManager = model.overlayManager else { return }
        do {
            diffText = try await overlayManager.diff(fork)
        } catch {
            model.banner = BannerError(error)
        }
    }

    private func save() async {
        guard let overlayManager = model.overlayManager else { return }
        do {
            try await overlayManager.write(text, to: fork)
            originalText = text
            model.loadForks()
        } catch {
            model.banner = BannerError(error)
        }
    }

    private func revert() async {
        guard let overlayManager = model.overlayManager else { return }
        do {
            try await overlayManager.revert(fork)
            load()
            model.loadForks()
        } catch {
            model.banner = BannerError(error)
        }
    }

    private func removeFork() async {
        guard let overlayManager = model.overlayManager else { return }
        do {
            try await overlayManager.remove(fork)
            model.loadForks()
            dismiss()
        } catch {
            model.banner = BannerError(error)
        }
    }
}
