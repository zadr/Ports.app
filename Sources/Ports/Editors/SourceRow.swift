import PortsConfig
import SwiftUI

struct SourceRow: View {
    let source: PortSource
    let onToggle: () -> Void
    let onMakeDefault: () -> Void
    let onDelete: () -> Void
    let onReindex: () -> Void
    let onSync: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { source.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
                flagsRow
            }
            Spacer()
            if source.isLocal {
                Button("Reindex", action: onReindex)
            } else {
                Button("Sync", action: onSync)
            }
            if !source.isDefault {
                Button("Make Default", action: onMakeDefault)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
    }

    private var flagsRow: some View {
        HStack(spacing: 6) {
            if source.isDefault {
                Label("Default", systemImage: "star.fill").font(.caption2)
            }
            if !source.isSynchronized {
                Label("No Sync", systemImage: "arrow.triangle.2.circlepath.circle.slash").font(.caption2)
            }
            if source.isLocal {
                Label("Local", systemImage: "folder").font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
    }
}
