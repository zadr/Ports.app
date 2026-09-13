import Testing
@testable import PortsCLI

@Suite("PortOutputParser.installed")
struct InstalledParserTests {
    @Test("parses multiple versions of one name, active flag, and no variants")
    func multipleVersions() {
        let text = """
          android-platform-tools @36.0.0_0
          android-platform-tools @36.0.2_0 (active)
          zlib @1.3.2_0 (active)
        """
        let ports = PortOutputParser.installed(text)
        #expect(ports.count == 3)

        #expect(ports[0].name == "android-platform-tools")
        #expect(ports[0].version == "36.0.0")
        #expect(ports[0].revision == 0)
        #expect(ports[0].isActive == false)
        #expect(ports[0].variants.isEmpty)

        #expect(ports[1].name == "android-platform-tools")
        #expect(ports[1].version == "36.0.2")
        #expect(ports[1].isActive == true)

        #expect(ports[2].name == "zlib")
        #expect(ports[2].version == "1.3.2")
        #expect(ports[2].revision == 0)
        #expect(ports[2].isActive == true)
    }

    @Test("parses + and - variant markers appended to the version token")
    func variantSigns() {
        let text = "  cairo @1.18.4_2+quartz+x11 (active)\n  zlib @1.3.2_0+universal-x11\n"
        let ports = PortOutputParser.installed(text)
        #expect(ports.count == 2)
        #expect(ports[0].variants == ["+quartz", "+x11"])
        #expect(ports[1].variants == ["+universal", "-x11"])
        #expect(ports[1].isActive == false)
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(PortOutputParser.installed("").isEmpty)
    }
}

@Suite("PortOutputParser.outdated")
struct OutdatedParserTests {
    @Test("parses whitespace padded columns")
    func basicRows() {
        let text = """
        bash                           5.3.9_0 < 5.3.15_0
        tcl                            8.6.17_0 < 8.6.18_0
        """
        let rows = PortOutputParser.outdated(text)
        #expect(rows.count == 2)
        #expect(rows[0].name == "bash")
        #expect(rows[0].installedVersion == "5.3.9_0")
        #expect(rows[0].availableVersion == "5.3.15_0")
        #expect(rows[0].note == nil)
        #expect(rows[1].name == "tcl")
    }

    @Test("keeps a trailing parenthetical note joined back together")
    func trailingNote() {
        let platformRow = PortOutputParser.outdated(
            "someport   1.0_0 < 1.1_0 (platform mismatch)"
        )
        #expect(platformRow.first?.note == "(platform mismatch)")

        let epochRow = PortOutputParser.outdated(
            "otherport   1.0_0 < 2.0_0 (epoch 1 < 2)"
        )
        #expect(epochRow.first?.note == "(epoch 1 < 2)")
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(PortOutputParser.outdated("").isEmpty)
    }
}

@Suite("PortOutputParser.searchResults")
struct SearchParserTests {
    @Test("parses tab separated name, version, categories, description")
    func basicRows() {
        let text = "zlib\t1.3.2\tarchivers\tzlib lossless data-compression library\n" +
            "zlib-ng\t2.3.3\tarchivers\tzlib replacement with optimizations"
        let results = PortOutputParser.searchResults(text)
        #expect(results.count == 2)
        #expect(results[0].name == "zlib")
        #expect(results[0].version == "1.3.2")
        #expect(results[0].categories == ["archivers"])
        #expect(results[0].summary == "zlib lossless data-compression library")
        #expect(results[1].name == "zlib-ng")
    }

    @Test("handles empty tab fields without dropping the row")
    func emptyFields() {
        let results = PortOutputParser.searchResults("foo\t1.0\t\t")
        #expect(results.count == 1)
        #expect(results[0].categories.isEmpty)
        #expect(results[0].summary.isEmpty)
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(PortOutputParser.searchResults("").isEmpty)
    }
}

@Suite("PortOutputParser.info")
struct InfoParserTests {
    @Test("parses the full tab separated line in flag order")
    func fullLine() {
        let text = "zlib\t1.3.2\t0\tuniversal\tarchivers\thttps://www.zlib.net/\t" +
            "zlib lossless data-compression library\tzlib is designed to be a free library.\t" +
            "zlib\tryandesign@macports.org ryandesign,openmaintainer"
        let info = PortOutputParser.info(text)
        #expect(info != nil)
        #expect(info?.name == "zlib")
        #expect(info?.version == "1.3.2")
        #expect(info?.revision == 0)
        #expect(info?.variantNames == ["universal"])
        #expect(info?.categories == ["archivers"])
        #expect(info?.homepage == "https://www.zlib.net/")
        #expect(info?.summary == "zlib lossless data-compression library")
        #expect(info?.license == "zlib")
        #expect(info?.maintainers == ["ryandesign@macports.org", "ryandesign,openmaintainer"])
    }

    @Test("missing trailing tab fields are treated as empty rather than failing")
    func shortLine() {
        let info = PortOutputParser.info("foo\t1.0\t0")
        #expect(info?.name == "foo")
        #expect(info?.maintainers.isEmpty == true)
    }

    @Test("empty input yields nil")
    func empty() {
        #expect(PortOutputParser.info("") == nil)
    }
}

@Suite("PortOutputParser.variants")
struct VariantParserTests {
    @Test("parses unselected variants with leading spaces")
    func unselected() {
        let variants = PortOutputParser.variants("   universal: Build for multiple architectures")
        #expect(variants.count == 1)
        #expect(variants[0].name == "universal")
        #expect(variants[0].summary == "Build for multiple architectures")
        #expect(variants[0].isSelected == false)
    }

    @Test("parses [+] and [-] prefixes as selection markers")
    func selectionMarkers() {
        let text = "[+]quartz: Enable Quartz backend\n[-]x11: Enable X11 backend\n   universal: multi-arch"
        let variants = PortOutputParser.variants(text)
        #expect(variants.count == 3)
        #expect(variants[0].isSelected == true)
        #expect(variants[0].name == "quartz")
        #expect(variants[1].isSelected == false)
        #expect(variants[1].name == "x11")
        #expect(variants[2].isSelected == false)
    }

    @Test("empty input yields no rows")
    func empty() {
        #expect(PortOutputParser.variants("").isEmpty)
    }
}

@Suite("PortOutputParser.dependencies")
struct DependenciesParserTests {
    @Test("parses a single labeled line with one value")
    func singleLabel() {
        let deps = PortOutputParser.dependencies("Extract Dependencies: xz")
        #expect(deps.extract == ["xz"])
        #expect(deps.library.isEmpty)
        #expect(deps.all == ["xz"])
    }

    @Test("parses comma separated values across multiple labels")
    func multipleLabels() {
        let text = """
        Library Dependencies: a, b, c
        Build Dependencies: cmake
        Runtime Dependencies:
        """
        let deps = PortOutputParser.dependencies(text)
        #expect(deps.library == ["a", "b", "c"])
        #expect(deps.build == ["cmake"])
        #expect(deps.runtime.isEmpty)
    }

    @Test("empty input yields an empty dependency set")
    func empty() {
        #expect(PortOutputParser.dependencies("").isEmpty)
    }
}

@Suite("PortOutputParser.diskUsage")
struct DiskUsageParserTests {
    @Test("converts KiB from the real zlib sample")
    func kibibytes() {
        #expect(PortOutputParser.diskUsage("647.02 KiB zlib") == 662548)
    }

    @Test("converts B, MiB, and GiB")
    func otherUnits() {
        #expect(PortOutputParser.diskUsage("10 B name") == 10)
        #expect(PortOutputParser.diskUsage("2.5 MiB name") == 2_621_440)
        #expect(PortOutputParser.diskUsage("1 GiB name") == 1_073_741_824)
    }

    @Test("empty input is zero")
    func empty() {
        #expect(PortOutputParser.diskUsage("") == 0)
    }
}
