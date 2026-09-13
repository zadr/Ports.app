import Foundation
import PortsCLI
import PortsConfig
import PortsOverlay
import PortsShell

@Observable
final class PortsModel {
    enum StartupState {
        case loading
        case ready
        case portMissing
    }

    var startupState: StartupState = .loading
    var environment: PortsEnvironment?
    var client: PortClient?

    var installed: [InstalledPort] = []
    var outdated: [OutdatedPort] = []
    var requestedNames: Set<String> = []
    var forks: [PortfileFork] = []

    var configuration: MacPortsConfiguration?
    var sourcesConfiguration: SourcesConfiguration?
    var variantsConfiguration: VariantsConfiguration?
    var overlayManager: OverlayManager?

    var selectedSection: SidebarSection = .installed
    var selectedPortName: String?
    var editingFork: PortfileFork?

    var infoCache: [String: PortInfo] = [:]
    var variantsCache: [String: [PortVariant]] = [:]
    var dependenciesCache: [String: PortDependencies] = [:]
    var dependentsCache: [String: [String]] = [:]
    var contentsCache: [String: [String]] = [:]
    var diskUsageCache: [String: Int64] = [:]

    let operationRunner = OperationRunner()
    var banner: BannerError?

    var customizedCount: Int { forks.count }

    // MARK: - Startup

    func bootstrap() async {
        startupState = .loading
        do {
            let environment = try await PortsEnvironment.detect()
            self.environment = environment
            let client = PortClient(environment: environment)
            self.client = client
            startupState = .ready
            await loadAll()
        } catch PortsCLIError.portMissing {
            startupState = .portMissing
        } catch {
            banner = BannerError(error)
            startupState = .portMissing
        }
    }

    /// Prepends the chosen executable's directory to PATH and retries detection.
    func useManualExecutable(at path: String) async {
        let directory = URL(filePath: path).deletingLastPathComponent().path(percentEncoded: false)
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", "\(directory):\(existing)", 1)
        await bootstrap()
    }

    // MARK: - List loading

    func loadAll() async {
        async let installedTask: Void = loadInstalled()
        async let outdatedTask: Void = loadOutdated()
        async let requestedTask: Void = loadRequested()
        _ = await (installedTask, outdatedTask, requestedTask)
        loadConfigurations()
        loadForks()
    }

    func loadInstalled() async {
        guard let client else { return }
        do { installed = try await client.installed() } catch { banner = BannerError(error) }
    }

    func loadOutdated() async {
        guard let client else { return }
        do { outdated = try await client.outdated() } catch { banner = BannerError(error) }
    }

    func loadRequested() async {
        guard let client else { return }
        do { requestedNames = try await client.requestedNames() } catch { banner = BannerError(error) }
    }

    func loadConfigurations() {
        guard let environment else { return }
        do {
            configuration = try MacPortsConfiguration.load(path: environment.macPortsConfPath)
            let sources = try SourcesConfiguration.load(path: environment.sourcesConfPath)
            sourcesConfiguration = sources
            variantsConfiguration = try VariantsConfiguration.load(path: environment.variantsConfPath)
            if let client {
                overlayManager = OverlayManager(trees: OverlayManager.trees(from: sources), client: client)
            }
        } catch {
            banner = BannerError(error)
        }
    }

    func loadForks() {
        guard let overlayManager else { return }
        do { forks = try overlayManager.forks() } catch { banner = BannerError(error) }
    }

    // MARK: - Detail loading, cached per port name

    func info(for name: String) async -> PortInfo? {
        if let cached = infoCache[name] { return cached }
        guard let client else { return nil }
        do {
            let info = try await client.info(name)
            infoCache[name] = info
            return info
        } catch {
            banner = BannerError(error)
            return nil
        }
    }

    func variants(for name: String) async -> [PortVariant] {
        if let cached = variantsCache[name] { return cached }
        guard let client else { return [] }
        do {
            let variants = try await client.variants(name)
            variantsCache[name] = variants
            return variants
        } catch {
            banner = BannerError(error)
            return []
        }
    }

    func dependencies(for name: String) async -> PortDependencies? {
        if let cached = dependenciesCache[name] { return cached }
        guard let client else { return nil }
        do {
            let dependencies = try await client.dependencies(name)
            dependenciesCache[name] = dependencies
            return dependencies
        } catch {
            banner = BannerError(error)
            return nil
        }
    }

    func dependents(for name: String) async -> [String] {
        if let cached = dependentsCache[name] { return cached }
        guard let client else { return [] }
        do {
            let names = try await client.dependents(name)
            dependentsCache[name] = names
            return names
        } catch {
            banner = BannerError(error)
            return []
        }
    }

    func contents(for name: String) async -> [String] {
        if let cached = contentsCache[name] { return cached }
        guard let client else { return [] }
        do {
            let files = try await client.contents(name)
            contentsCache[name] = files
            return files
        } catch {
            banner = BannerError(error)
            return []
        }
    }

    func diskUsage(for name: String) async -> Int64? {
        if let cached = diskUsageCache[name] { return cached }
        guard let client else { return nil }
        do {
            let size = try await client.diskUsage(name)
            diskUsageCache[name] = size
            return size
        } catch {
            banner = BannerError(error)
            return nil
        }
    }

    // MARK: - Operations

    func run(_ operation: PortOperation) {
        guard let client else { return }
        operationRunner.start(operation, client: client) { [weak self] success in
            guard let self, success else { return }
            Task { await self.refreshAfterOperation() }
        }
    }

    private func refreshAfterOperation() async {
        await loadInstalled()
        await loadOutdated()
        await loadRequested()
        infoCache.removeAll()
        loadForks()
    }

    // MARK: - Portfile forks

    func existingFork(for name: String) -> PortfileFork? {
        forks.first { $0.name == name }
    }

    func openPortfileEditor(for name: String) async {
        if let existing = existingFork(for: name) {
            editingFork = existing
            return
        }
        editingFork = await fork(name)
    }

    private func fork(_ name: String) async -> PortfileFork? {
        do {
            let tree = try await editableTree()
            guard let overlayManager else { throw PortsModelError.noSourcesConfiguration }
            let fork = try await overlayManager.fork(name, into: tree)
            loadForks()
            return fork
        } catch {
            banner = BannerError(error)
            return nil
        }
    }

    /// Edited Portfiles need a local tree that outranks the default source.
    /// When sources.conf has none, one is created and registered here.
    private func editableTree() async throws -> OverlayTree {
        if let existing = overlayManager?.trees.first(where: {
            $0.precedesDefaultSource && PrivilegedFile.isWritable($0.path)
        }) {
            return existing
        }
        guard let configuration = sourcesConfiguration else {
            throw PortsModelError.noSourcesConfiguration
        }
        let path = URL(filePath: "\(NSHomeDirectory())/.ports", directoryHint: .notDirectory)
        let tree = try await OverlayManager.createTree(at: path.path(percentEncoded: false))

        var sources = configuration.sources
        sources.removeAll { $0.url == path.absoluteString }
        sources.insert(PortSource(url: path.absoluteString, isEnabled: true), at: 0)
        try await configuration.save(configuration.applying(sources))
        loadConfigurations()
        return tree
    }
}

enum PortsModelError: LocalizedError {
    case noSourcesConfiguration

    var errorDescription: String? {
        switch self {
        case .noSourcesConfiguration: "sources.conf could not be read."
        }
    }
}
