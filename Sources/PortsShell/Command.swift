import Foundation

public struct Command: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectory: String?

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
    }

    /// Single shell line equivalent to this command, quoted for `/bin/sh`.
    public var shellLine: String {
        let assignments = environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.quote($0.value))" }
        let parts = assignments + [Self.quote(executable)] + arguments.map(Self.quote)
        return parts.joined(separator: " ")
    }

    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct CommandOutput: Sendable, Hashable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32

    public init(standardOutput: String, standardError: String, exitCode: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }

    /// Standard output split into lines, blank lines removed.
    public var lines: [String] {
        standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

public struct OutputLine: Sendable, Hashable, Identifiable {
    public enum Channel: Sendable, Hashable {
        case standardOutput
        case standardError
    }

    public let id: Int
    public var channel: Channel
    public var text: String

    public init(id: Int, channel: Channel, text: String) {
        self.id = id
        self.channel = channel
        self.text = text
    }
}

public enum ProcessEvent: Sendable, Hashable {
    case output(OutputLine)
    case exit(Int32)
}

public enum Privilege: Sendable, Hashable {
    case direct
    case administrator
}

public enum ShellError: Error, Sendable, Hashable {
    case executableMissing(String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, standardError: String)
    case authorizationDenied
    case notWritable(String)
}

extension ShellError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableMissing(let path): "Executable not found: \(path)"
        case .launchFailed(let reason): "Could not start process: \(reason)"
        case .nonZeroExit(let code, let error):
            error.isEmpty ? "Command failed with status \(code)." : error
        case .authorizationDenied: "Administrator authorization was refused."
        case .notWritable(let path): "No write permission for \(path)."
        }
    }
}
