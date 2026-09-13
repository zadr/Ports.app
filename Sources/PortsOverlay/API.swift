import Foundation
import PortsCLI
import PortsConfig
import PortsShell

/// A local port tree listed in sources.conf with a `file://` URL. Portfiles
/// placed here shadow the rsync tree when the tree precedes it in the file.
public struct OverlayTree: Sendable, Hashable, Identifiable {
    public var path: String
    public var isIndexed: Bool
    public var precedesDefaultSource: Bool

    public init(path: String, isIndexed: Bool = false, precedesDefaultSource: Bool = true) {
        self.path = path
        self.isIndexed = isIndexed
        self.precedesDefaultSource = precedesDefaultSource
    }

    public var id: String { path }
    public var name: String { URL(filePath: path).lastPathComponent }
}

/// A Portfile copied into an overlay tree so it can be edited. The pristine
/// upstream copy is kept in application support and is the diff baseline.
public struct PortfileFork: Sendable, Hashable, Identifiable {
    public var name: String
    public var category: String
    public var treePath: String
    public var isModified: Bool
    /// Upstream Portfile changed after the fork was taken, so the fork may be stale.
    public var upstreamChanged: Bool
    public var hasBaseline: Bool

    public init(
        name: String,
        category: String,
        treePath: String,
        isModified: Bool = false,
        upstreamChanged: Bool = false,
        hasBaseline: Bool = false
    ) {
        self.name = name
        self.category = category
        self.treePath = treePath
        self.isModified = isModified
        self.upstreamChanged = upstreamChanged
        self.hasBaseline = hasBaseline
    }

    public var id: String { "\(treePath)/\(category)/\(name)" }
    public var directory: String { "\(treePath)/\(category)/\(name)" }
    public var portfilePath: String { "\(directory)/Portfile" }
    public var filesDirectory: String { "\(directory)/files" }
}

public enum OverlayError: Error, Sendable, Hashable {
    case noTreeConfigured
    case upstreamPortfileMissing(String)
    case alreadyForked(String)
    case notForked(String)
    case indexFailed(String)
}

public struct OverlayManager: Sendable {
    public var trees: [OverlayTree]
    public var client: PortClient

    public init(trees: [OverlayTree], client: PortClient) {
        self.trees = trees
        self.client = client
    }

    /// Derives trees from the `file://` entries of sources.conf, in file order.
    public static func trees(from configuration: SourcesConfiguration) -> [OverlayTree] {
        let defaultLineIndex = configuration.sources.first(where: \.isDefault)?.lineIndex
        return configuration.sources.compactMap { source in
            guard source.isEnabled, source.url.hasPrefix("file://"),
                  let path = URL(string: source.url)?.path(percentEncoded: false), !path.isEmpty
            else { return nil }
            return OverlayTree(
                path: path,
                isIndexed: FileManager.default.fileExists(atPath: "\(path)/PortIndex"),
                precedesDefaultSource: defaultLineIndex.map { source.lineIndex < $0 } ?? true
            )
        }
    }

    /// Every port directory present in the overlay trees.
    public func forks() throws -> [PortfileFork] {
        var forks: [PortfileFork] = []
        for tree in trees {
            for category in try portEntries(at: tree.path) {
                for name in try portEntries(at: "\(tree.path)/\(category)") {
                    let portfilePath = "\(tree.path)/\(category)/\(name)/Portfile"
                    guard FileManager.default.fileExists(atPath: portfilePath) else { continue }
                    forks.append(makeFork(name: name, category: category, treePath: tree.path))
                }
            }
        }
        return forks
    }

    /// Copies the upstream Portfile and its `files` directory into `tree`,
    /// records the baseline, and reindexes the tree.
    public func fork(_ name: String, into tree: OverlayTree) async throws -> PortfileFork {
        let upstreamPortfilePath = try await resolvedUpstreamPortfilePath(name)

        // `port file` already resolving inside one of our trees means the port
        // is forked and indexed there, wherever precedence put it.
        guard !trees.contains(where: { upstreamPortfilePath.hasPrefix($0.path + "/") }) else {
            throw OverlayError.alreadyForked(name)
        }

        let category: String
        if let info = try? await client.info(name), !info.primaryCategory.isEmpty {
            category = info.primaryCategory
        } else {
            category = categoryFromUpstreamPath(upstreamPortfilePath)
        }

        let portDirectory = "\(tree.path)/\(category)/\(name)"
        let destinationPortfile = "\(portDirectory)/Portfile"
        guard !FileManager.default.fileExists(atPath: destinationPortfile) else {
            throw OverlayError.alreadyForked(name)
        }

        let upstreamDirectory = URL(filePath: upstreamPortfilePath)
            .deletingLastPathComponent().path(percentEncoded: false)
        let upstreamFilesDirectory = "\(upstreamDirectory)/files"

        // A fork that stops half way leaves the tree indexing a Portfile with no
        // baseline behind it, so anything after the first write is undone on failure.
        do {
            try await PrivilegedFile.createDirectory(portDirectory)
            try await PrivilegedFile.copyItem(at: upstreamPortfilePath, to: destinationPortfile)
            if FileManager.default.fileExists(atPath: upstreamFilesDirectory) {
                try await PrivilegedFile.copyItem(at: upstreamFilesDirectory, to: "\(portDirectory)/files")
            }

            try await writeBaseline(
                name: name,
                category: category,
                treePath: tree.path,
                upstreamPortfilePath: upstreamPortfilePath,
                upstreamFilesDirectory: upstreamFilesDirectory
            )

            try await waitForReindex(tree)
        } catch {
            try? await PrivilegedFile.remove(portDirectory)
            throw error
        }

        return PortfileFork(
            name: name,
            category: category,
            treePath: tree.path,
            isModified: false,
            upstreamChanged: false,
            hasBaseline: true
        )
    }

    public func portfileText(_ fork: PortfileFork) throws -> String {
        guard FileManager.default.fileExists(atPath: fork.portfilePath) else {
            throw OverlayError.notForked(fork.name)
        }
        return try PrivilegedFile.read(fork.portfilePath)
    }

    /// Writes the Portfile and reindexes the tree so `port` sees the change.
    public func write(_ text: String, to fork: PortfileFork) async throws {
        guard FileManager.default.fileExists(atPath: fork.directory) else {
            throw OverlayError.notForked(fork.name)
        }
        try await PrivilegedFile.write(text, to: fork.portfilePath)
        try await waitForReindex(tree(containing: fork))
    }

    /// Unified diff of the fork against its upstream baseline.
    public func diff(_ fork: PortfileFork) async throws -> String {
        guard FileManager.default.fileExists(atPath: fork.portfilePath) else {
            throw OverlayError.notForked(fork.name)
        }
        let referencePath = FileManager.default.fileExists(atPath: fork.baselinePortfilePath)
            ? fork.baselinePortfilePath
            : try await resolvedUpstreamPortfilePath(fork.name)

        let output = try await Shell.run(
            Command(executable: "/usr/bin/diff", arguments: ["-u", referencePath, fork.portfilePath])
        )
        guard output.exitCode == 0 || output.exitCode == 1 else {
            throw ShellError.nonZeroExit(code: output.exitCode, standardError: output.standardError)
        }
        return output.standardOutput
    }

    /// Restores the fork from the current upstream Portfile.
    public func revert(_ fork: PortfileFork) async throws {
        guard FileManager.default.fileExists(atPath: fork.directory) else {
            throw OverlayError.notForked(fork.name)
        }
        let tree = try tree(containing: fork)
        let upstreamPortfilePath = try await resolvedUpstreamPortfilePath(fork.name)
        let upstreamFilesDirectory = URL(filePath: upstreamPortfilePath)
            .deletingLastPathComponent().appending(path: "files").path(percentEncoded: false)

        try await PrivilegedFile.write(try PrivilegedFile.read(upstreamPortfilePath), to: fork.portfilePath)
        try await PrivilegedFile.remove(fork.filesDirectory)
        if FileManager.default.fileExists(atPath: upstreamFilesDirectory) {
            try await PrivilegedFile.copyItem(at: upstreamFilesDirectory, to: fork.filesDirectory)
        }

        try await writeBaseline(
            name: fork.name,
            category: fork.category,
            treePath: fork.treePath,
            upstreamPortfilePath: upstreamPortfilePath,
            upstreamFilesDirectory: upstreamFilesDirectory
        )

        try await waitForReindex(tree)
    }

    /// Deletes the fork so the upstream Portfile applies again.
    public func remove(_ fork: PortfileFork) async throws {
        guard FileManager.default.fileExists(atPath: fork.directory) else {
            throw OverlayError.notForked(fork.name)
        }
        let tree = try tree(containing: fork)
        try await PrivilegedFile.remove(fork.directory)
        try await PrivilegedFile.remove(fork.baselineDirectory)
        try await waitForReindex(tree)
    }

    public func reindex(_ tree: OverlayTree) -> AsyncThrowingStream<ProcessEvent, any Error> {
        client.stream(.reindex(directory: tree.path))
    }

    /// Creates a tree directory and returns it, ready to be added to sources.conf.
    public static func createTree(at path: String) async throws -> OverlayTree {
        try await PrivilegedFile.createDirectory(path)
        return OverlayTree(path: path, isIndexed: false, precedesDefaultSource: true)
    }

    /// Files under the fork's `files` directory, which hold patches.
    public func patchFiles(_ fork: PortfileFork) throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fork.filesDirectory) else { return [] }
        return try manager.contentsOfDirectory(atPath: fork.filesDirectory)
            .filter { !$0.hasPrefix(".") && !isDirectory("\(fork.filesDirectory)/\($0)") }
            .sorted()
            .map { "\(fork.filesDirectory)/\($0)" }
    }

    public func patchText(_ path: String) throws -> String { try PrivilegedFile.read(path) }
    public func writePatch(_ text: String, to path: String) async throws {
        try await PrivilegedFile.write(text, to: path)
    }

    /// Adds a `patchfiles` entry naming `fileName` when the Portfile lacks one.
    public static func portfileAddingPatch(_ text: String, fileName: String) -> String {
        var lines = text.components(separatedBy: "\n")

        if let block = PatchfilesDirective.existingBlock(in: lines) {
            guard !PatchfilesDirective.tokens(in: lines, block: block).contains(fileName) else { return text }
            lines[block.upperBound] += " \(fileName)"
            return lines.joined(separator: "\n")
        }

        let newLine = "patchfiles".padding(toLength: 28, withPad: " ", startingAt: 0) + fileName
        PatchfilesDirective.insert(newLine, at: PatchfilesDirective.insertionIndex(in: lines), into: &lines)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Private helpers

extension OverlayManager {
    /// Directory names under `path`, skipping dotfiles and the `files`/`work`
    /// directories that live inside a port directory, not beside one.
    private func portEntries(at path: String) throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else { return [] }
        return try manager.contentsOfDirectory(atPath: path)
            .filter { !$0.hasPrefix(".") && $0 != "files" && $0 != "work" }
            .filter { isDirectory("\(path)/\($0)") }
            .sorted()
    }

    private func isDirectory(_ path: String) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &flag) && flag.boolValue
    }

    private func makeFork(name: String, category: String, treePath: String) -> PortfileFork {
        let portfilePath = "\(treePath)/\(category)/\(name)/Portfile"
        let baselinePath = OverlayManager.baselinePortfilePath(treePath: treePath, category: category, name: name)
        let hasBaseline = FileManager.default.fileExists(atPath: baselinePath)

        let forkText = try? String(contentsOfFile: portfilePath, encoding: .utf8)
        let baselineText = hasBaseline ? try? String(contentsOfFile: baselinePath, encoding: .utf8) : nil
        let upstreamText = try? String(
            contentsOfFile: currentUpstreamPortfilePath(category: category, name: name),
            encoding: .utf8
        )

        return PortfileFork(
            name: name,
            category: category,
            treePath: treePath,
            isModified: differs(forkText, baselineText ?? upstreamText),
            upstreamChanged: differs(baselineText, upstreamText),
            hasBaseline: hasBaseline
        )
    }

    private func differs(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs != rhs
    }

    /// Best-effort location of the default rsync mirror's on-disk checkout, used
    /// only so `forks()` can answer `isModified`/`upstreamChanged` without an
    /// async round trip through `port file`. `diff`, `fork` and `revert` use
    /// `client.portfilePath` instead, which is correct for any mirror.
    private func currentUpstreamPortfilePath(category: String, name: String) -> String {
        "\(client.environment.prefix)/var/macports/sources/rsync.macports.org" +
            "/macports/release/tarballs/ports/\(category)/\(name)/Portfile"
    }

    private func categoryFromUpstreamPath(_ path: String) -> String {
        URL(filePath: path).deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    private func resolvedUpstreamPortfilePath(_ name: String) async throws -> String {
        guard let path = try? await client.portfilePath(name), !path.isEmpty else {
            throw OverlayError.upstreamPortfileMissing(name)
        }
        return path
    }

    private func tree(containing fork: PortfileFork) throws -> OverlayTree {
        guard let tree = trees.first(where: { $0.path == fork.treePath }) else {
            throw OverlayError.noTreeConfigured
        }
        return tree
    }

    private func waitForReindex(_ tree: OverlayTree) async throws {
        for try await event in reindex(tree) {
            if case .exit(let code) = event, code != 0 {
                throw OverlayError.indexFailed(tree.path)
            }
        }
    }

    /// The baseline is the pristine upstream Portfile plus its `files` directory,
    /// kept outside the tree so a fork's edits never touch it.
    private func writeBaseline(
        name: String,
        category: String,
        treePath: String,
        upstreamPortfilePath: String,
        upstreamFilesDirectory: String
    ) async throws {
        let directory = OverlayManager.baselineDirectory(treePath: treePath, category: category, name: name)
        try await PrivilegedFile.createDirectory(directory)
        try await PrivilegedFile.write(try PrivilegedFile.read(upstreamPortfilePath), to: "\(directory)/Portfile")

        let filesDirectory = "\(directory)/files"
        try? await PrivilegedFile.remove(filesDirectory)
        if FileManager.default.fileExists(atPath: upstreamFilesDirectory) {
            try await PrivilegedFile.copyItem(at: upstreamFilesDirectory, to: filesDirectory)
        }
    }
}
