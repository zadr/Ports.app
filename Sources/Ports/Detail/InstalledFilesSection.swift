import SwiftUI

struct InstalledFilesSection: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @State private var files: [String]?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Installed Files", isExpanded: $isExpanded) {
            if let files {
                if files.isEmpty {
                    Text("No files recorded.").foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading) {
                        ForEach(files, id: \.self) { path in
                            Text(path).font(.caption).monospaced()
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded, files == nil else { return }
            files = await model.contents(for: portName)
        }
    }
}
