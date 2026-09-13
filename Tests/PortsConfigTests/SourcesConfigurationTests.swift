import Foundation
import Testing
@testable import PortsConfig

@Suite("SourcesConfiguration")
struct SourcesConfigurationTests {
    static let lines = [
        "# MacPorts system-wide configuration file for ports tree sources.",
        "#",
        "# header continues.",
        "",
        "file:///Users/z/.ports",
        "#file:///Users/z/.old-ports [nosync]",
        "rsync://rsync.macports.org/macports/release/tarballs/ports.tar [default]",
        "",
    ]
    static let text = lines.joined(separator: "\n")

    @Test("parses enabled, disabled, and default-flagged sources")
    func parsesSources() {
        let config = SourcesConfiguration.parse(text: Self.text, path: "/tmp/sources.conf")
        #expect(config.sources.count == 3)

        #expect(config.sources[0].url == "file:///Users/z/.ports")
        #expect(config.sources[0].isEnabled == true)
        #expect(config.sources[0].flags == [])

        #expect(config.sources[1].url == "file:///Users/z/.old-ports")
        #expect(config.sources[1].isEnabled == false)
        #expect(config.sources[1].flags == ["nosync"])

        #expect(config.sources[2].url == "rsync://rsync.macports.org/macports/release/tarballs/ports.tar")
        #expect(config.sources[2].isEnabled == true)
        #expect(config.sources[2].isDefault == true)
    }

    @Test("applying reorders sources, keeps a disabled entry commented, and preserves the header")
    func applyingReordersAndPreservesHeader() {
        let config = SourcesConfiguration.parse(text: Self.text, path: "/tmp/sources.conf")
        var reordered = config.sources
        reordered.swapAt(0, 2)
        let updated = config.applying(reordered)

        let expectedLines = [
            "# MacPorts system-wide configuration file for ports tree sources.",
            "#",
            "# header continues.",
            "",
            "rsync://rsync.macports.org/macports/release/tarballs/ports.tar [default]",
            "#file:///Users/z/.old-ports [nosync]",
            "file:///Users/z/.ports",
            "",
        ]
        #expect(updated == expectedLines.joined(separator: "\n"))

        let reparsed = SourcesConfiguration.parse(text: updated, path: "/tmp/sources.conf")
        #expect(reparsed.sources.map(\.url) == reordered.map(\.url))
        #expect(reparsed.sources.first { $0.url.contains("old-ports") }?.isEnabled == false)
    }
}

@Suite("SourcesConfiguration.validate")
struct SourcesValidateTests {
    let config = SourcesConfiguration(path: "/tmp/sources.conf", text: "", sources: [])

    @Test("flags when no source is the default")
    func noDefault() {
        let sources = [PortSource(url: "rsync://example.com/ports.tar")]
        #expect(config.validate(sources) == ["No source is flagged as the default."])
    }

    @Test("flags when more than one source is the default")
    func multipleDefaults() {
        let sources = [
            PortSource(url: "rsync://a.example.com/ports.tar", flags: ["default"]),
            PortSource(url: "rsync://b.example.com/ports.tar", flags: ["default"]),
        ]
        #expect(config.validate(sources) == ["More than one source is flagged as the default."])
    }

    @Test("flags a local tree listed after the default remote tree")
    func localAfterDefault() {
        let sources = [
            PortSource(url: "rsync://example.com/ports.tar", flags: ["default"]),
            PortSource(url: "file:///nonexistent/ports-fixture"),
        ]
        #expect(
            config.validate(sources) == [
                "Local source file:///nonexistent/ports-fixture is listed after the default remote source; its Portfiles will never take precedence.",
                "Local source path does not exist: /nonexistent/ports-fixture",
            ]
        )
    }

    @Test("flags a file:// source whose path does not exist")
    func missingLocalPath() {
        let sources = [PortSource(url: "file:///nonexistent/ports-fixture", flags: ["default"])]
        #expect(config.validate(sources) == ["Local source path does not exist: /nonexistent/ports-fixture"])
    }

    @Test("flags a duplicate URL")
    func duplicateURL() {
        let sources = [
            PortSource(url: "rsync://example.com/ports.tar", flags: ["default"]),
            PortSource(url: "rsync://example.com/ports.tar"),
        ]
        #expect(config.validate(sources) == ["Source is listed more than once: rsync://example.com/ports.tar"])
    }

    @Test("returns no problems for a sound list")
    func sound() {
        let sources = [
            PortSource(url: "file:///tmp"),
            PortSource(url: "rsync://example.com/ports.tar", flags: ["default"]),
        ]
        #expect(config.validate(sources).isEmpty)
    }
}

@Suite("PortSource")
struct PortSourceTests {
    @Test("localPath decodes file:// URLs, including percent-encoding")
    func fileURLLocalPath() {
        let source = PortSource(url: "file:///Users/z/My%20Ports")
        #expect(source.localPath == "/Users/z/My Ports")
    }

    @Test("localPath accepts a bare absolute path")
    func barePathLocalPath() {
        let source = PortSource(url: "/Users/z/.ports")
        #expect(source.isLocal == true)
        #expect(source.localPath == "/Users/z/.ports")
    }

    @Test("localPath is nil for remote URLs")
    func remoteLocalPathNil() {
        let source = PortSource(url: "rsync://rsync.macports.org/macports/release/tarballs/ports.tar")
        #expect(source.isLocal == false)
        #expect(source.localPath == nil)
    }

    @Test("displayName uses the last path component for local trees")
    func localDisplayName() {
        #expect(PortSource(url: "file:///Users/z/.ports").displayName == ".ports")
    }

    @Test("displayName shortens remote URLs to host plus last path component")
    func remoteDisplayName() {
        let source = PortSource(url: "rsync://rsync.macports.org/macports/release/tarballs/ports.tar")
        #expect(source.displayName == "rsync.macports.org/…/ports.tar")
    }
}
