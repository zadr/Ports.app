import Foundation

/// File operations that fall back to an authorization prompt when the current
/// user cannot write the target. A MacPorts prefix under `/opt/local` is owned
/// by root; a prefix inside a home directory is not.
public enum PrivilegedFile {
    /// Permission is decided by the nearest existing ancestor, since creating a
    /// port directory also creates the category directory above it.
    public static func isWritable(_ path: String) -> Bool {
        let manager = FileManager.default
        var candidate = URL(filePath: path)
        while true {
            let current = candidate.path(percentEncoded: false)
            if manager.fileExists(atPath: current) { return manager.isWritableFile(atPath: current) }
            let parent = candidate.deletingLastPathComponent()
            if parent.path(percentEncoded: false) == current { return false }
            candidate = parent
        }
    }

    /// `.direct` when the user can write the path, `.administrator` otherwise.
    public static func privilege(for path: String) -> Privilege {
        isWritable(path) ? .direct : .administrator
    }

    public static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public static func write(_ contents: String, to path: String) async throws {
        let target = URL(filePath: path)
        if isWritable(path) {
            try contents.write(to: target, atomically: true, encoding: .utf8)
            return
        }
        let staged = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ports-write-\(UUID().uuidString)")
        try contents.write(to: staged, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: staged) }
        // cp writes through an existing inode, so destination ownership and mode survive.
        try await Shell.check(
            Command(
                executable: "/bin/cp",
                arguments: [staged.path(percentEncoded: false), path]
            ),
            privilege: .administrator
        )
    }

    public static func createDirectory(_ path: String) async throws {
        if FileManager.default.fileExists(atPath: path) { return }
        if isWritable(path) {
            try FileManager.default.createDirectory(
                at: URL(filePath: path),
                withIntermediateDirectories: true
            )
            return
        }
        try await Shell.check(
            Command(executable: "/bin/mkdir", arguments: ["-p", path]),
            privilege: .administrator
        )
    }

    public static func copyItem(at source: String, to destination: String) async throws {
        if isWritable(destination) {
            let target = URL(filePath: destination)
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: URL(filePath: source), to: target)
            return
        }
        try await Shell.check(
            Command(executable: "/bin/cp", arguments: ["-R", source, destination]),
            privilege: .administrator
        )
    }

    public static func remove(_ path: String) async throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        if isWritable(path) {
            try FileManager.default.removeItem(at: URL(filePath: path))
            return
        }
        try await Shell.check(
            Command(executable: "/bin/rm", arguments: ["-rf", path]),
            privilege: .administrator
        )
    }
}
