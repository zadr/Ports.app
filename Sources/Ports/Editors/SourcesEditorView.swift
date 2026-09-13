import AppKit
import PortsCLI
import PortsConfig
import PortsOverlay
import SwiftUI

struct SourcesEditorView: View {
    @Environment(PortsModel.self) private var model
    @State private var sources: [PortSource] = []
    @State private var warnings: [String] = []
    @State private var newURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !warnings.isEmpty {
                warningBanner
            }
            List {
                ForEach(sources) { source in
                    SourceRow(
                        source: source,
                        onToggle: { toggleEnabled(source) },
                        onMakeDefault: { makeDefault(source) },
                        onDelete: { delete(source) },
                        onReindex: { reindex(source) },
                        onSync: { model.run(.sync) }
                    )
                }
                .onMove(perform: move)
            }
            layoutHelp
            addBar
        }
        .navigationTitle("Sources")
        .task(id: model.sourcesConfiguration?.sources) {
            sources = model.sourcesConfiguration?.sources ?? []
            revalidate()
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15))
    }

    private var layoutHelp: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("A local tree holds Portfiles at tree/category/port/Portfile, with patches in that port's files directory.")
            Text("A port resolves against the first tree that indexes it, so a tree above the default source overrides upstream. Reindex a tree after changing it by hand.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var addBar: some View {
        HStack {
            TextField("Remote source URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
            Button("Add") { addRemote() }
                .disabled(newURL.isEmpty)
            Button("Add Local Tree…") { addLocalTree() }
        }
        .padding(8)
    }

    private func revalidate() {
        warnings = model.sourcesConfiguration?.validate(sources) ?? []
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        revalidate()
        persist()
    }

    private func toggleEnabled(_ source: PortSource) {
        guard let index = sources.firstIndex(of: source) else { return }
        sources[index].isEnabled.toggle()
        revalidate()
        persist()
    }

    private func makeDefault(_ source: PortSource) {
        for index in sources.indices {
            var flags = sources[index].flags.filter { $0 != "default" }
            if sources[index].id == source.id { flags.append("default") }
            sources[index].flags = flags
        }
        revalidate()
        persist()
    }

    private func delete(_ source: PortSource) {
        sources.removeAll { $0.id == source.id }
        revalidate()
        persist()
    }

    private func addRemote() {
        sources.append(PortSource(url: newURL, flags: [], isEnabled: true, lineIndex: sources.count))
        newURL = ""
        revalidate()
        persist()
    }

    private func addLocalTree() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        Task {
            do {
                if !FileManager.default.fileExists(atPath: path) {
                    _ = try await OverlayManager.createTree(at: path)
                }
                // sources.conf entries carry no trailing slash, so the panel URL is renormalized.
                let sourceURL = URL(filePath: path, directoryHint: .notDirectory).absoluteString
                sources.insert(PortSource(url: sourceURL, flags: [], isEnabled: true, lineIndex: 0), at: 0)
                revalidate()
                persist()
            } catch {
                model.banner = BannerError(error)
            }
        }
    }

    private func persist() {
        guard let configuration = model.sourcesConfiguration else { return }
        let text = configuration.applying(sources)
        Task {
            do {
                try await configuration.save(text)
                model.loadConfigurations()
            } catch {
                model.banner = BannerError(error)
            }
        }
    }

    private func reindex(_ source: PortSource) {
        guard let path = source.localPath else { return }
        model.run(.reindex(directory: path))
    }
}
