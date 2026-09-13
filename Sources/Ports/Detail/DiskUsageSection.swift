import SwiftUI

struct DiskUsageSection: View {
    let portName: String

    @Environment(PortsModel.self) private var model
    @State private var bytes: Int64?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Disk Usage", isExpanded: $isExpanded) {
            if let bytes {
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            } else {
                ProgressView()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded, bytes == nil else { return }
            bytes = await model.diskUsage(for: portName)
        }
    }
}
