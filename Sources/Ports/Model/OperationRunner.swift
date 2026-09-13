import Foundation
import PortsCLI
import PortsShell

/// Runs one `PortOperation` at a time through `PortClient.stream` and keeps a
/// short history so the console can show what just happened.
@Observable
final class OperationRunner {
    struct Run: Identifiable {
        let id = UUID()
        var operation: PortOperation
        var commandLine: String
        var lines: [OutputLine] = []
        var isRunning = true
        var exitCode: Int32?
        var failure: String?
    }

    var current: Run?
    var history: [Run] = []
    var isCollapsed = false

    private var task: Task<Void, Never>?
    private static let historyLimit = 5

    func start(_ operation: PortOperation, client: PortClient, onFinish: @escaping (Bool) -> Void) {
        task?.cancel()
        let commandLine = ([client.environment.executable] + client.arguments(for: operation))
            .joined(separator: " ")
        current = Run(operation: operation, commandLine: commandLine)
        isCollapsed = false

        task = Task { [weak self] in
            var success = false
            do {
                for try await event in client.stream(operation) {
                    guard let self else { return }
                    switch event {
                    case .output(let line):
                        self.current?.lines.append(line)
                    case .exit(let code):
                        self.current?.exitCode = code
                        self.current?.isRunning = false
                        success = code == 0
                    }
                }
            } catch {
                self?.current?.failure = error.localizedDescription
                self?.current?.isRunning = false
                success = false
            }
            guard let self, let finished = self.current else { return }
            self.history.insert(finished, at: 0)
            if self.history.count > Self.historyLimit {
                self.history.removeLast(self.history.count - Self.historyLimit)
            }
            onFinish(success)
        }
    }

    func cancel() {
        task?.cancel()
    }
}
