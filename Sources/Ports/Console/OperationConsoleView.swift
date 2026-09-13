import PortsShell
import SwiftUI

struct OperationConsoleView: View {
    @Environment(PortsModel.self) private var model

    private var runner: OperationRunner { model.operationRunner }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            if !runner.isCollapsed {
                content
                    .frame(height: 220)
            }
        }
        .background(.bar)
    }

    private var header: some View {
        HStack {
            if let current = runner.current {
                if current.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: current.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(current.exitCode == 0 ? .green : .red)
                }
                Text(current.commandLine)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            } else {
                Text("No Operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if runner.current?.isRunning == true {
                Button("Cancel") { runner.cancel() }
                    .font(.caption)
            }
            Button {
                runner.isCollapsed.toggle()
            } label: {
                Image(systemName: runner.isCollapsed ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let current = runner.current {
            RunDetailView(run: current)
        } else if let last = runner.history.first {
            RunDetailView(run: last)
        } else {
            Text("Operations you run will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RunDetailView: View {
    let run: OperationRunner.Run

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.commandLine)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(run.lines) { line in
                            Text(line.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(line.channel == .standardError ? .red : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: run.lines.count) { _, _ in
                    if let lastID = run.lines.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            if let exitCode = run.exitCode {
                Text("Exit code \(exitCode)")
                    .font(.caption)
                    .foregroundStyle(exitCode == 0 ? Color.secondary : Color.red)
                    .padding(.horizontal, 12)
            }
            if let failure = run.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 4)
    }
}
