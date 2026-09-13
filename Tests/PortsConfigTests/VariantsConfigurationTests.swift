import Testing
@testable import PortsConfig

@Suite("VariantsConfiguration")
struct VariantsConfigurationTests {
    static let lines = [
        "# MacPorts system-wide global variants configuration file.",
        "",
        "# Any variants listed here are applied to all port builds.",
        "#",
        "# Example:",
        "#   -x11 +no_x11 +quartz",
        "",
        "-x11 +quartz",
        "+universal",
    ]
    static let text = lines.joined(separator: "\n")

    @Test("parses variant tokens, ignoring commented example lines")
    func parsesVariants() {
        let config = VariantsConfiguration.parse(text: Self.text, path: "/tmp/variants.conf")
        #expect(config.variants == ["-x11", "+quartz", "+universal"])
    }

    @Test("an all-commented file parses to no variants")
    func allCommentedParsesEmpty() {
        let text = Self.lines.prefix(6).joined(separator: "\n")
        let config = VariantsConfiguration.parse(text: text, path: "/tmp/variants.conf")
        #expect(config.variants.isEmpty)
    }

    @Test("applying keeps header comments and writes one token per line")
    func applyingVariants() {
        let config = VariantsConfiguration.parse(text: Self.text, path: "/tmp/variants.conf")
        let updated = config.applying(["+gcc48", "-x11"])

        let expectedLines = [
            "# MacPorts system-wide global variants configuration file.",
            "",
            "# Any variants listed here are applied to all port builds.",
            "#",
            "# Example:",
            "#   -x11 +no_x11 +quartz",
            "",
            "+gcc48",
            "-x11",
        ]
        #expect(updated == expectedLines.joined(separator: "\n"))
    }

    @Test("applying round-trips through parse")
    func roundTrip() {
        let config = VariantsConfiguration.parse(text: Self.text, path: "/tmp/variants.conf")
        let updated = config.applying(["+gcc48", "-x11"])
        let reparsed = VariantsConfiguration.parse(text: updated, path: "/tmp/variants.conf")
        #expect(reparsed.variants == ["+gcc48", "-x11"])
    }
}
