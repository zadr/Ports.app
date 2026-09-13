import Foundation
import PortsShell

func fetchInstalledPorts(environment: PortsEnvironment) async throws -> [InstalledPort] {
    let output = try await query(["installed"], environment: environment)
    let requested = try await fetchRequestedNames(environment: environment)
    var ports = parseInstalledPorts(output)
    for index in ports.indices where requested.contains(ports[index].name) {
        ports[index].isRequested = true
    }
    return ports
}

func fetchRequestedNames(environment: PortsEnvironment) async throws -> Set<String> {
    let output = try await query(["echo", "requested"], environment: environment)
    return Set(nonEmptyLines(output))
}

func fetchOutdatedPorts(environment: PortsEnvironment) async throws -> [OutdatedPort] {
    parseOutdatedPorts(try await query(["outdated"], environment: environment))
}

func fetchSearchResults(term: String, environment: PortsEnvironment) async throws -> [PortSearchResult] {
    let escaped = term.trimmingCharacters(in: .whitespacesAndNewlines).filter { !"*?[]\\".contains($0) }
    guard !escaped.isEmpty else { return [] }
    let output = try await query(
        [
            "search", "--line", "--name", "--version", "--categories", "--description",
            "--glob", "*\(escaped)*",
        ],
        environment: environment,
        quiet: false
    )
    return parseSearchResults(output)
}

func fetchPortInfo(name: String, environment: PortsEnvironment) async throws -> PortInfo {
    let output = try await query(
        [
            "info", "--line", "--index", "--name", "--version", "--revision",
            "--variants", "--categories", "--homepage", "--description",
            "--long_description", "--license", "--maintainers", name,
        ],
        environment: environment
    )
    guard let info = parsePortInfo(output) else {
        throw PortsCLIError.unreadableOutput(output)
    }
    return info
}

func fetchPortVariants(name: String, environment: PortsEnvironment) async throws -> [PortVariant] {
    parsePortVariants(try await query(["variants", name], environment: environment))
}

func fetchPortDependencies(name: String, environment: PortsEnvironment) async throws -> PortDependencies {
    parsePortDependencies(try await query(["deps", name], environment: environment))
}

func fetchDependents(name: String, environment: PortsEnvironment) async throws -> [String] {
    nonEmptyLines(try await query(["dependents", name], environment: environment))
}

func fetchContents(name: String, environment: PortsEnvironment) async throws -> [String] {
    nonEmptyLines(try await query(["contents", name], environment: environment))
}

func fetchDiskUsage(name: String, environment: PortsEnvironment) async throws -> Int64 {
    parseDiskUsage(try await query(["space", name], environment: environment))
}

func fetchNotes(name: String, environment: PortsEnvironment) async throws -> [String] {
    nonEmptyLines(try await query(["notes", name], environment: environment))
}

/// Absolute path of the Portfile `port` resolves for `name`, from `port file`.
func fetchPortfilePath(name: String, environment: PortsEnvironment) async throws -> String {
    let output = try await query(["file", name], environment: environment, quiet: false)
    return try firstLine(output)
}

/// Absolute path of the port directory, from `port dir`.
func fetchPortDirectory(name: String, environment: PortsEnvironment) async throws -> String {
    let output = try await query(["dir", name], environment: environment, quiet: false)
    return try firstLine(output)
}

/// Live output of a mutating action. The final element is `.exit`.
func makePortStream(
    operation: PortOperation,
    environment: PortsEnvironment
) -> AsyncThrowingStream<ProcessEvent, any Error> {
    let executable: String
    let currentDirectory: String?
    switch operation {
    case .reindex(let directory):
        executable = environment.portIndexBinary
        currentDirectory = directory
    default:
        executable = environment.executable
        currentDirectory = nil
    }
    let command = Command(
        executable: executable,
        arguments: portOperationArguments(operation),
        currentDirectory: currentDirectory
    )
    let privilege: Privilege = operationWritesPrefix(operation) ? environment.privilege : .direct
    return Shell.stream(command, privilege: privilege)
}

/// Runs a read-only `port` query and returns raw stdout. `-q` is added unless `quiet` is false.
private func query(_ arguments: [String], environment: PortsEnvironment, quiet: Bool = true) async throws -> String {
    let fullArguments = quiet ? ["-q"] + arguments : arguments
    do {
        let output = try await Shell.check(Command(executable: environment.executable, arguments: fullArguments))
        return output.standardOutput
    } catch let error as ShellError {
        throw PortsCLIError.commandFailed(
            operation: arguments.joined(separator: " "),
            message: error.errorDescription ?? "\(error)"
        )
    }
}

private func firstLine(_ output: String) throws -> String {
    guard let path = nonEmptyLines(output).first else {
        throw PortsCLIError.unreadableOutput(output)
    }
    return path
}

private func nonEmptyLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}
