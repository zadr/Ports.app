import Foundation
import PortsCLI
import Testing

@testable import PortsOverlay

@Suite("OverlayManager.forks()")
struct ForkEnumerationTests {
    private func makeManager(root: URL) -> OverlayManager {
        let environment = PortsEnvironment(
            executable: "/usr/bin/true",
            prefix: root.path(percentEncoded: false),
            version: "1",
            requiresAdministrator: false
        )
        let tree = OverlayTree(path: root.path(percentEncoded: false), isIndexed: false, precedesDefaultSource: true)
        return OverlayManager(trees: [tree], client: PortClient(environment: environment))
    }

    private func writePortfile(_ manager: FileManager, at directory: URL) throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        manager.createFile(atPath: directory.appending(path: "Portfile").path(percentEncoded: false), contents: Data())
    }

    @Test("walks category then port directories, skipping files, work and dotfiles")
    func enumeratesPortDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "overlay-forks-\(UUID().uuidString)")
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        // The two real forks that must surface.
        let fooport = root.appending(path: "devel/fooport")
        try writePortfile(manager, at: fooport)
        try manager.createDirectory(at: fooport.appending(path: "files"), withIntermediateDirectories: true)
        manager.createFile(atPath: fooport.appending(path: "files/patch.diff").path(percentEncoded: false), contents: Data())
        try manager.createDirectory(at: fooport.appending(path: "work/junk"), withIntermediateDirectories: true)

        try writePortfile(manager, at: root.appending(path: "multimedia/barport"))

        // Traps: directories literally named "files"/"work" or starting with a
        // dot, each holding a Portfile, at both the category and port level.
        try writePortfile(manager, at: root.appending(path: "files"))
        try writePortfile(manager, at: root.appending(path: "work"))
        try writePortfile(manager, at: root.appending(path: ".hidden/port"))
        try writePortfile(manager, at: root.appending(path: "devel/files"))
        try writePortfile(manager, at: root.appending(path: "devel/work"))
        try writePortfile(manager, at: root.appending(path: "devel/.hiddenport"))

        // A category with no Portfile-bearing subdirectory contributes nothing.
        try manager.createDirectory(at: root.appending(path: "net/empty"), withIntermediateDirectories: true)

        // Files at tree root that must not be mistaken for category directories.
        manager.createFile(atPath: root.appending(path: "PortIndex").path(percentEncoded: false), contents: Data())
        manager.createFile(atPath: root.appending(path: "PortIndex.quick").path(percentEncoded: false), contents: Data())

        let forks = try makeManager(root: root).forks()
        let ids = Set(forks.map { "\($0.category)/\($0.name)" })

        #expect(ids == Set(["devel/fooport", "multimedia/barport"]))
    }

    @Test("baseline paths are derived from a stable 16-character hash of the tree path")
    func baselinePathDerivation() {
        let path = OverlayManager.baselinePortfilePath(treePath: "/Users/z/.ports", category: "devel", name: "glib2-devel")
        let identifier = OverlayManager.treeIdentifier("/Users/z/.ports")

        #expect(identifier.count == 16)
        #expect(identifier.allSatisfy { $0.isHexDigit })
        #expect(path == "\(OverlayManager.baselinesRoot())/\(identifier)/devel/glib2-devel/Portfile")
        #expect(OverlayManager.treeIdentifier("/Users/z/.ports") == identifier)
        #expect(OverlayManager.treeIdentifier("/Users/z/.other-ports") != identifier)
    }

    @Test("a hand-made fork with no baseline reports hasBaseline false")
    func handMadeForkHasNoBaseline() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "overlay-forks-\(UUID().uuidString)")
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        try writePortfile(manager, at: root.appending(path: "devel/handmade"))

        let forks = try makeManager(root: root).forks()
        #expect(forks.count == 1)
        #expect(forks[0].hasBaseline == false)
        #expect(forks[0].upstreamChanged == false)
    }
}
