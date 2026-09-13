import PortsCLI
import SwiftUI

/// Queries `PortClient.search` with a debounce, rather than filtering an
/// already-loaded list.
struct SearchView: View {
    @Environment(PortsModel.self) private var model
    @State private var query = ""
    @State private var results: [PortSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        @Bindable var model = model
        List(results, selection: $model.selectedPortName) { result in
            SearchResultRow(result: result)
                .tag(result.name)
        }
        .searchable(text: $query, prompt: "Search ports")
        .navigationTitle("Search")
        .task(id: query) {
            guard !query.isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search Ports",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a name or keyword.")
                )
            } else if isSearching {
                ProgressView()
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func performSearch() async {
        guard let client = model.client else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await client.search(query)
        } catch {
            model.banner = BannerError(error)
        }
    }
}

private struct SearchResultRow: View {
    let result: PortSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.name)
                Spacer()
                Text(result.version)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !result.categories.isEmpty {
                Text(result.categories.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
