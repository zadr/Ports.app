import Foundation
import PortsShell

// MARK: - Models

public struct InstalledPort: Sendable, Hashable, Identifiable {
    public var name: String
    public var version: String
    public var revision: Int
    /// Variant tokens as MacPorts writes them, for example `+universal`, `-x11`.
    public var variants: [String]
    public var isActive: Bool
    public var isRequested: Bool

    public init(
        name: String,
        version: String,
        revision: Int,
        variants: [String] = [],
        isActive: Bool = true,
        isRequested: Bool = false
    ) {
        self.name = name
        self.version = version
        self.revision = revision
        self.variants = variants
        self.isActive = isActive
        self.isRequested = isRequested
    }

    public var id: String { "\(name)@\(version)_\(revision)\(variants.joined())" }
    public var versionString: String { "\(version)_\(revision)" }
    public var variantSummary: String { variants.joined() }
}

public struct OutdatedPort: Sendable, Hashable, Identifiable {
    public var name: String
    public var installedVersion: String
    public var availableVersion: String
    /// Trailing qualifier such as `(platform mismatch)` or `(epoch 1 < 2)`.
    public var note: String?

    public init(name: String, installedVersion: String, availableVersion: String, note: String? = nil) {
        self.name = name
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.note = note
    }

    public var id: String { name }
}

public struct PortSearchResult: Sendable, Hashable, Identifiable {
    public var name: String
    public var version: String
    public var categories: [String]
    public var summary: String

    public init(name: String, version: String, categories: [String], summary: String) {
        self.name = name
        self.version = version
        self.categories = categories
        self.summary = summary
    }

    public var id: String { name }
}

public struct PortInfo: Sendable, Hashable {
    public var name: String
    public var version: String
    public var revision: Int
    public var categories: [String]
    public var maintainers: [String]
    public var summary: String
    public var details: String
    public var homepage: String
    public var license: String
    public var variantNames: [String]

    public init(
        name: String,
        version: String = "",
        revision: Int = 0,
        categories: [String] = [],
        maintainers: [String] = [],
        summary: String = "",
        details: String = "",
        homepage: String = "",
        license: String = "",
        variantNames: [String] = []
    ) {
        self.name = name
        self.version = version
        self.revision = revision
        self.categories = categories
        self.maintainers = maintainers
        self.summary = summary
        self.details = details
        self.homepage = homepage
        self.license = license
        self.variantNames = variantNames
    }

    public var versionString: String { "\(version)_\(revision)" }
    public var primaryCategory: String { categories.first ?? "" }
}

public struct PortVariant: Sendable, Hashable, Identifiable {
    public var name: String
    public var summary: String
    public var isSelected: Bool

    public init(name: String, summary: String = "", isSelected: Bool = false) {
        self.name = name
        self.summary = summary
        self.isSelected = isSelected
    }

    public var id: String { name }
}

public struct PortDependencies: Sendable, Hashable {
    public var library: [String]
    public var build: [String]
    public var runtime: [String]
    public var extract: [String]
    public var fetch: [String]
    public var test: [String]

    public init(
        library: [String] = [],
        build: [String] = [],
        runtime: [String] = [],
        extract: [String] = [],
        fetch: [String] = [],
        test: [String] = []
    ) {
        self.library = library
        self.build = build
        self.runtime = runtime
        self.extract = extract
        self.fetch = fetch
        self.test = test
    }

    public var all: [String] {
        var seen: Set<String> = []
        return (library + build + runtime + extract + fetch + test).filter { seen.insert($0).inserted }
    }

    public var isEmpty: Bool { all.isEmpty }
}

/// Where the `port` binary lives, which prefix it manages, and whether writing
/// to that prefix needs an authorization prompt.
public struct PortsEnvironment: Sendable, Hashable {
    public var executable: String
    public var prefix: String
    public var version: String
    public var requiresAdministrator: Bool

    public init(executable: String, prefix: String, version: String, requiresAdministrator: Bool) {
        self.executable = executable
        self.prefix = prefix
        self.version = version
        self.requiresAdministrator = requiresAdministrator
    }

    public var privilege: Privilege { requiresAdministrator ? .administrator : .direct }
    public var configurationDirectory: String { "\(prefix)/etc/macports" }
    public var macPortsConfPath: String { "\(configurationDirectory)/macports.conf" }
    public var sourcesConfPath: String { "\(configurationDirectory)/sources.conf" }
    public var variantsConfPath: String { "\(configurationDirectory)/variants.conf" }
    public var portIndexBinary: String {
        URL(filePath: executable).deletingLastPathComponent()
            .appending(path: "portindex").path(percentEncoded: false)
    }

    /// Locates `port` on PATH, reads its prefix and version, and tests prefix
    /// write permission. Throws `PortsCLIError.portMissing` when absent.
    public static func detect() async throws -> PortsEnvironment {
        try await detectPortsEnvironment()
    }
}

public enum PortsCLIError: Error, Sendable, Hashable {
    case portMissing
    case commandFailed(operation: String, message: String)
    case unreadableOutput(String)
}

// MARK: - Operations

public enum PortOperation: Sendable, Hashable {
    case install(name: String, variants: [String])
    /// `version` is a full `version_revision+variants` specifier, needed to pick
    /// one of several installed builds. Nil uninstalls every installed version.
    case uninstall(name: String, version: String?)
    case upgrade(names: [String])
    case upgradeOutdated
    case activate(name: String, version: String?)
    case deactivate(name: String)
    case clean(name: String)
    case selfupdate
    case sync
    case reclaim
    /// `portindex` run inside a local port tree.
    case reindex(directory: String)
    case custom(arguments: [String])

    public var title: String { operationTitle(self) }
    /// False for read-only actions and for `reindex`, which writes only the tree.
    public var writesPrefix: Bool { operationWritesPrefix(self) }
}

// MARK: - Client

public struct PortClient: Sendable {
    public var environment: PortsEnvironment

    public init(environment: PortsEnvironment) {
        self.environment = environment
    }

    public func installed() async throws -> [InstalledPort] { try await fetchInstalledPorts(environment: environment) }
    public func requestedNames() async throws -> Set<String> { try await fetchRequestedNames(environment: environment) }
    public func outdated() async throws -> [OutdatedPort] { try await fetchOutdatedPorts(environment: environment) }
    public func search(_ term: String) async throws -> [PortSearchResult] {
        try await fetchSearchResults(term: term, environment: environment)
    }
    public func info(_ name: String) async throws -> PortInfo {
        try await fetchPortInfo(name: name, environment: environment)
    }
    public func variants(_ name: String) async throws -> [PortVariant] {
        try await fetchPortVariants(name: name, environment: environment)
    }
    public func dependencies(_ name: String) async throws -> PortDependencies {
        try await fetchPortDependencies(name: name, environment: environment)
    }
    public func dependents(_ name: String) async throws -> [String] {
        try await fetchDependents(name: name, environment: environment)
    }
    public func contents(_ name: String) async throws -> [String] {
        try await fetchContents(name: name, environment: environment)
    }
    public func diskUsage(_ name: String) async throws -> Int64 {
        try await fetchDiskUsage(name: name, environment: environment)
    }
    public func notes(_ name: String) async throws -> [String] { try await fetchNotes(name: name, environment: environment) }

    /// Absolute path of the Portfile `port` resolves for `name`, from `port file`.
    public func portfilePath(_ name: String) async throws -> String {
        try await fetchPortfilePath(name: name, environment: environment)
    }
    /// Absolute path of the port directory, from `port dir`.
    public func portDirectory(_ name: String) async throws -> String {
        try await fetchPortDirectory(name: name, environment: environment)
    }

    /// Live output of a mutating action. The final element is `.exit`.
    public func stream(_ operation: PortOperation) -> AsyncThrowingStream<ProcessEvent, any Error> {
        makePortStream(operation: operation, environment: environment)
    }

    /// Argument vector the operation runs, exposed so the UI can show the exact command.
    public func arguments(for operation: PortOperation) -> [String] { portOperationArguments(operation) }
}

// MARK: - Parsers

/// Pure text parsers, separated from process execution so they can be tested.
public enum PortOutputParser {
    /// Parses `port -q installed`: `  name @1.2.3_0+variant (active)`.
    public static func installed(_ text: String) -> [InstalledPort] { parseInstalledPorts(text) }
    /// Parses `port -q outdated`: `name  1.2_0 < 1.3_0  (note)`.
    public static func outdated(_ text: String) -> [OutdatedPort] { parseOutdatedPorts(text) }
    /// Parses tab separated `port search --line --name --version --categories --description`.
    public static func searchResults(_ text: String) -> [PortSearchResult] { parseSearchResults(text) }
    /// Parses tab separated `port info --line` with the field order used by `PortClient.info`.
    public static func info(_ text: String) -> PortInfo? { parsePortInfo(text) }
    /// Parses `port -q variants`: `   name: summary`, `[+]name: summary`.
    public static func variants(_ text: String) -> [PortVariant] { parsePortVariants(text) }
    /// Parses `port -q deps`: `Library Dependencies: a, b, c`.
    public static func dependencies(_ text: String) -> PortDependencies { parsePortDependencies(text) }
    /// Parses `port -q space`: `647.02 KiB name` into bytes.
    public static func diskUsage(_ text: String) -> Int64 { parseDiskUsage(text) }
}
