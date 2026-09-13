import Foundation
import Testing

@testable import PortsOverlay

@Suite("OverlayManager.portfileAddingPatch")
struct PatchTextTests {
    @Test("appends to an existing single-line patchfiles directive")
    func existingLine() {
        let text = """
        name                        example
        patchfiles                  patch-a.diff
        checksums                   sha256  abc
        """
        let originalLines = text.components(separatedBy: "\n")

        let result = OverlayManager.portfileAddingPatch(text, fileName: "patch-b.diff")
        let lines = result.components(separatedBy: "\n")

        #expect(lines[0] == originalLines[0])
        #expect(lines[1] == originalLines[1] + " patch-b.diff")
        #expect(lines[2] == originalLines[2])
    }

    @Test("appends to a multi-line continued patchfiles directive")
    func continuedLine() {
        let text = """
        patchfiles                  patch-a.diff \\
                                     patch-b.diff
        checksums                   sha256  abc
        """
        let originalLines = text.components(separatedBy: "\n")

        let result = OverlayManager.portfileAddingPatch(text, fileName: "patch-c.diff")
        let lines = result.components(separatedBy: "\n")

        #expect(lines[0] == originalLines[0])
        #expect(lines[1] == originalLines[1] + " patch-c.diff")
        #expect(lines[2] == originalLines[2])
    }

    @Test("does nothing when the file name is already listed on a single line")
    func alreadyListed() {
        let text = """
        patchfiles                  patch-a.diff patch-b.diff
        checksums                   sha256  abc
        """
        #expect(OverlayManager.portfileAddingPatch(text, fileName: "patch-b.diff") == text)
    }

    @Test("already-listed detection reaches across a continuation")
    func alreadyListedContinued() {
        let text = """
        patchfiles                  patch-a.diff \\
                                     patch-b.diff
        checksums                   sha256  abc
        """
        #expect(OverlayManager.portfileAddingPatch(text, fileName: "patch-b.diff") == text)
    }

    @Test("inserts a new directive after the last checksums/distfiles/master_sites block")
    func insertsAfterMetadataBlock() throws {
        let text = """
        name                        example
        checksums                   rmd160  aaa \\
                                     sha256  bbb
        master_sites                gnome:sources/example/
        description                 An example port.
        configure.args-append       --foo
        """

        let result = OverlayManager.portfileAddingPatch(text, fileName: "patch-a.diff")
        let lines = result.components(separatedBy: "\n")
        let masterSitesIndex = try #require(lines.firstIndex { $0.hasPrefix("master_sites") })

        #expect(lines[masterSitesIndex + 1].hasPrefix("patchfiles"))
        #expect(lines[masterSitesIndex + 1].contains("patch-a.diff"))
    }

    @Test("falls back to inserting before the first configure/build/variant stanza")
    func insertsBeforeStanzaFallback() throws {
        let text = """
        name                        example
        description                 An example port.
        configure.args-append       --foo
        variant quartz {
            configure.args-append   --quartz
        }
        """

        let result = OverlayManager.portfileAddingPatch(text, fileName: "patch-a.diff")
        let lines = result.components(separatedBy: "\n")
        let variantIndex = try #require(lines.firstIndex { $0.hasPrefix("variant") })

        #expect(lines[variantIndex - 1].hasPrefix("patchfiles"))
        #expect(lines[variantIndex - 1].contains("patch-a.diff"))
    }

    @Test("patchfiles-append is a different directive and is left alone")
    func ignoresPatchfilesAppend() throws {
        let text = """
        name                        example
        checksums                   sha256  abc
        patchfiles-append           patch-a.diff
        """
        let originalLines = text.components(separatedBy: "\n")

        let result = OverlayManager.portfileAddingPatch(text, fileName: "patch-b.diff")
        let lines = result.components(separatedBy: "\n")
        let checksumsIndex = try #require(lines.firstIndex { $0.hasPrefix("checksums") })

        #expect(lines.contains(originalLines[2])) // patchfiles-append line untouched
        #expect(lines[checksumsIndex + 1].hasPrefix("patchfiles "))
        #expect(lines[checksumsIndex + 1].contains("patch-b.diff"))
    }
}
