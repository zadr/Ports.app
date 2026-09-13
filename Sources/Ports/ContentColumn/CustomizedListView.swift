import PortsOverlay
import SwiftUI

struct CustomizedListView: View {
    @Environment(PortsModel.self) private var model
    @State private var query = ""

    private var filtered: [PortfileFork] {
        guard !query.isEmpty else { return model.forks }
        return model.forks.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        List(filtered, selection: $model.selectedPortName) { fork in
            ForkRow(fork: fork)
                .tag(fork.name)
        }
        .searchable(text: $query)
        .navigationTitle("Customized")
    }
}

private struct ForkRow: View {
    let fork: PortfileFork

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(fork.name)
                Text(URL(filePath: fork.treePath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if fork.isModified {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Modified")
            }
            if fork.upstreamChanged {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Upstream changed since fork")
            }
        }
    }
}
