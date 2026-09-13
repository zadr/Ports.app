import Foundation
import Testing
@testable import PortsConfig

@Suite("MacPortsConfiguration")
struct MacPortsConfigurationTests {
    static let liveLines = [
        "# MacPorts system-wide configuration file.",
        "# Commented-out values are defaults unless otherwise noted.",
        "",
        "# Directory under which MacPorts should install ports. This must be",
        "# where MacPorts itself is installed.",
        "prefix              \t/Users/z/.usr",
        "",
        "# User to run operations as when MacPorts drops privileges.",
        "#macportsuser        \tz",
        "",
        "startupitem_install\tno",
        "",
    ]
    static let live = liveLines.joined(separator: "\n")

    static let defaultsLines = [
        "# MacPorts system-wide configuration file.",
        "# Commented-out values are defaults unless otherwise noted.",
        "",
        "# Directory under which MacPorts should install ports. This must be",
        "# where MacPorts itself is installed.",
        "prefix              \t/opt/local",
        "",
        "# User to run operations as when MacPorts drops privileges.",
        "#macportsuser        \tmacports",
        "",
        "# Type of generated StartupItems.",
        "# This setting only applies when building ports from source.",
        "startupitem_install\tno",
        "",
    ]
    static let defaults = defaultsLines.joined(separator: "\n")

    @Test("parses a live key with its documentation")
    func liveKey() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let prefix = config.setting("prefix")
        #expect(prefix?.value == "/Users/z/.usr")
        #expect(prefix?.isCommentedOut == false)
        #expect(prefix?.lineIndex == 5)
        #expect(
            prefix?.documentation
                == "Directory under which MacPorts should install ports. This must be\nwhere MacPorts itself is installed."
        )
    }

    @Test("parses a commented-out key as disabled, with its documentation")
    func commentedKey() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let user = config.setting("macportsuser")
        #expect(user?.value == "z")
        #expect(user?.isCommentedOut == true)
        #expect(user?.documentation == "User to run operations as when MacPorts drops privileges.")
    }

    @Test("a key with no immediately preceding comment block has empty documentation")
    func noDocumentation() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        #expect(config.setting("startupitem_install")?.documentation == "")
    }

    @Test("documentation collapses blank comment lines into paragraph breaks")
    func documentationParagraphBreak() {
        let text = [
            "# First paragraph line one.",
            "# First paragraph line two.",
            "#",
            "# Second paragraph.",
            "somekey\tvalue",
        ].joined(separator: "\n")
        let config = MacPortsConfiguration.parse(text: text, path: "/tmp/macports.conf")
        #expect(
            config.setting("somekey")?.documentation
                == "First paragraph line one.\nFirst paragraph line two.\n\nSecond paragraph."
        )
    }

    @Test("defaults supply defaultValue for a matching key")
    func defaultsSupplyValue() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf", defaults: Self.defaults)
        #expect(config.setting("prefix")?.defaultValue == "/opt/local")
        #expect(config.setting("macportsuser")?.defaultValue == "macports")
    }

    @Test("defaults fill documentation the live file lacks")
    func defaultsFillDocumentation() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf", defaults: Self.defaults)
        #expect(
            config.setting("startupitem_install")?.documentation
                == "Type of generated StartupItems.\nThis setting only applies when building ports from source."
        )
    }

    @Test("value(for:) returns the live value, falling back to defaultValue when commented out")
    func valueFallback() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf", defaults: Self.defaults)
        #expect(config.value(for: "prefix") == "/Users/z/.usr")
        #expect(config.value(for: "macportsuser") == "macports")
        #expect(config.value(for: "nonexistent") == nil)
    }

    @Test("settingValue rewrites only the target line, preserving alignment")
    func settingValueRewritesLine() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let updated = config.settingValue("/opt/local", for: "prefix")

        var expectedLines = Self.liveLines
        expectedLines[config.setting("prefix")!.lineIndex] = "prefix              \t/opt/local"
        #expect(updated == expectedLines.joined(separator: "\n"))

        let reparsed = MacPortsConfiguration.parse(text: updated, path: "/tmp/macports.conf")
        #expect(reparsed.setting("prefix")?.value == "/opt/local")
        #expect(reparsed.setting("prefix")?.isCommentedOut == false)
    }

    @Test("settingValue uncomments a commented key in place")
    func settingValueUncomments() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let updated = config.settingValue("bob", for: "macportsuser")

        var expectedLines = Self.liveLines
        let index = config.setting("macportsuser")!.lineIndex
        expectedLines[index] = String(Self.liveLines[index].dropFirst()).replacingOccurrences(of: "z", with: "bob")
        #expect(updated == expectedLines.joined(separator: "\n"))

        let reparsed = MacPortsConfiguration.parse(text: updated, path: "/tmp/macports.conf")
        #expect(reparsed.setting("macportsuser")?.value == "bob")
        #expect(reparsed.setting("macportsuser")?.isCommentedOut == false)
    }

    @Test("settingValue appends an absent key at the end of the file")
    func settingValueAppendsMissingKey() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let updated = config.settingValue("yes", for: "portautoclean")

        let expectedLines = Array(Self.liveLines.dropLast()) + ["", "# Added by Ports.", "portautoclean\tyes", ""]
        #expect(updated == expectedLines.joined(separator: "\n"))

        let reparsed = MacPortsConfiguration.parse(text: updated, path: "/tmp/macports.conf")
        #expect(reparsed.setting("portautoclean")?.value == "yes")
        #expect(reparsed.setting("portautoclean")?.isCommentedOut == false)
    }

    @Test("clearingValue comments out a live key")
    func clearingValueComments() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        let updated = config.clearingValue(for: "prefix")

        var expectedLines = Self.liveLines
        let index = config.setting("prefix")!.lineIndex
        expectedLines[index] = "#" + Self.liveLines[index]
        #expect(updated == expectedLines.joined(separator: "\n"))

        let reparsed = MacPortsConfiguration.parse(text: updated, path: "/tmp/macports.conf")
        #expect(reparsed.setting("prefix")?.isCommentedOut == true)
    }

    @Test("clearingValue is a no-op for an already commented key")
    func clearingValueNoOpWhenCommented() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        #expect(config.clearingValue(for: "macportsuser") == Self.live)
    }

    @Test("clearingValue is a no-op for a missing key")
    func clearingValueNoOpWhenMissing() {
        let config = MacPortsConfiguration.parse(text: Self.live, path: "/tmp/macports.conf")
        #expect(config.clearingValue(for: "nonexistent") == Self.live)
    }

    @Test("load reads the sibling .default file automatically")
    func loadReadsDefaultsSibling() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ports-config-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let confPath = dir.appending(path: "macports.conf").path(percentEncoded: false)
        let defaultPath = confPath + ".default"
        try Self.live.write(toFile: confPath, atomically: true, encoding: .utf8)
        try Self.defaults.write(toFile: defaultPath, atomically: true, encoding: .utf8)

        let config = try MacPortsConfiguration.load(path: confPath)
        #expect(config.setting("prefix")?.defaultValue == "/opt/local")
    }

    @Test("load throws unreadable for a missing file")
    func loadMissingFileThrows() {
        #expect(throws: ConfigurationError.self) {
            _ = try MacPortsConfiguration.load(path: "/nonexistent/ports-config-test/macports.conf")
        }
    }
}
