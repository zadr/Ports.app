import Foundation
import PortsShell

/// Locates `port` on PATH, reads its prefix and version, and tests prefix write permission.
func detectPortsEnvironment() async throws -> PortsEnvironment {
    guard let executable = Shell.which("port") ?? knownInstallPath() else {
        throw PortsCLIError.portMissing
    }

    let resolvedExecutable = URL(filePath: executable).resolvingSymlinksInPath()
        .path(percentEncoded: false)
    let binDirectory = URL(filePath: resolvedExecutable).deletingLastPathComponent()
    let resolvedPrefix = binDirectory.deletingLastPathComponent().path(percentEncoded: false)

    let prefix: String
    if FileManager.default.fileExists(atPath: "\(resolvedPrefix)/etc/macports/macports.conf") {
        prefix = resolvedPrefix
    } else if let fallback = try? PrivilegedFile.read("/opt/local/etc/macports/macports.conf"),
              let configuredPrefix = confValue(fallback, key: "prefix") {
        prefix = configuredPrefix
    } else {
        prefix = resolvedPrefix
    }

    let versionOutput: CommandOutput
    do {
        versionOutput = try await Shell.check(Command(executable: executable, arguments: ["version"]))
    } catch let error as ShellError {
        throw PortsCLIError.commandFailed(operation: "version", message: error.errorDescription ?? "\(error)")
    }
    let version = parsePortVersion(versionOutput.standardOutput)

    let requiresAdministrator = !PrivilegedFile.isWritable("\(prefix)/var/macports")

    return PortsEnvironment(
        executable: executable,
        prefix: prefix,
        version: version,
        requiresAdministrator: requiresAdministrator
    )
}

/// An app bundle inherits the launchd PATH, which omits the directories a
/// MacPorts install usually lands in, so the common prefixes are probed directly.
private func knownInstallPath() -> String? {
    let home = NSHomeDirectory()
    let candidates = [
        "/opt/local/bin/port",
        "/usr/local/bin/port",
        "\(home)/.local/bin/port",
        "\(home)/.usr/bin/port",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// Reads `key` from a whitespace separated MacPorts `.conf` file, e.g. `prefix    /opt/local`.
private func confValue(_ text: String, key: String) -> String? {
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, fields[0] == Substring(key) else { continue }
        return String(fields[1])
    }
    return nil
}

/// Parses the `Version: 2.12.5` line from `port version`.
private func parsePortVersion(_ text: String) -> String {
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Version:") {
            return line.dropFirst("Version:".count).trimmingCharacters(in: .whitespaces)
        }
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
