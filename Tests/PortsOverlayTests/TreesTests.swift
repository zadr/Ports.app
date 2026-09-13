import Foundation
import PortsConfig
import Testing

@testable import PortsOverlay

@Suite("OverlayManager.trees(from:)")
struct TreesTests {
    @Test("keeps file:// entries in file order and reports whether each precedes the default")
    func ordering() {
        let sources = [
            PortSource(url: "file:///tmp/overlay-a", flags: [], isEnabled: true, lineIndex: 3),
            PortSource(url: "file:///tmp/overlay-b", flags: [], isEnabled: true, lineIndex: 5),
            PortSource(url: "rsync://example.test/ports.tar", flags: ["default"], isEnabled: true, lineIndex: 7),
            PortSource(url: "file:///tmp/overlay-c", flags: [], isEnabled: true, lineIndex: 9),
        ]
        let configuration = SourcesConfiguration(path: "/tmp/sources.conf", text: "", sources: sources)

        let trees = OverlayManager.trees(from: configuration)

        #expect(trees.map(\.path) == ["/tmp/overlay-a", "/tmp/overlay-b", "/tmp/overlay-c"])
        #expect(trees[0].precedesDefaultSource)
        #expect(trees[1].precedesDefaultSource)
        #expect(!trees[2].precedesDefaultSource)
    }

    @Test("no default entry means every local tree is reported as preceding")
    func noDefault() {
        let sources = [
            PortSource(url: "file:///tmp/overlay-a", flags: [], isEnabled: true, lineIndex: 0),
        ]
        let configuration = SourcesConfiguration(path: "/tmp/sources.conf", text: "", sources: sources)

        #expect(OverlayManager.trees(from: configuration).first?.precedesDefaultSource == true)
    }

    @Test("ignores non-file sources and disabled entries")
    func filtering() {
        let sources = [
            PortSource(url: "rsync://example.test/ports.tar", flags: ["default"], isEnabled: true, lineIndex: 0),
            PortSource(url: "file:///tmp/disabled", flags: [], isEnabled: false, lineIndex: 1),
        ]
        let configuration = SourcesConfiguration(path: "/tmp/sources.conf", text: "", sources: sources)

        #expect(OverlayManager.trees(from: configuration).isEmpty)
    }

    @Test("isIndexed reflects whether PortIndex exists at the tree root")
    func indexedDetection() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "overlay-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(
            atPath: root.appending(path: "PortIndex").path(percentEncoded: false),
            contents: nil
        )

        let sources = [
            PortSource(url: "file://\(root.path(percentEncoded: false))", flags: [], isEnabled: true, lineIndex: 0),
        ]
        let configuration = SourcesConfiguration(path: "/tmp/sources.conf", text: "", sources: sources)

        let trees = OverlayManager.trees(from: configuration)
        #expect(trees.count == 1)
        #expect(trees[0].isIndexed)
    }
}
