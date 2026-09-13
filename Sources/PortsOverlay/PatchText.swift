import Foundation

/// Pure text manipulation of a Portfile's `patchfiles` directive, kept apart
/// from `OverlayManager` so it can be exercised without touching a filesystem.
enum PatchfilesDirective {
    private static let checksumDirectives: Set<String> = ["checksums", "distfiles", "master_sites"]
    private static let stanzaFallbackDirectives: Set<String> = ["configure", "build", "variant"]

    /// The line range of the existing `patchfiles` statement, following `\`
    /// line continuations. `nil` when the Portfile has none (`patchfiles-append`
    /// and `patchfiles-replace` are different directives and don't match).
    static func existingBlock(in lines: [String]) -> ClosedRange<Int>? {
        guard let index = lines.firstIndex(where: { directiveWord($0) == "patchfiles" }) else { return nil }
        return blockRange(startingAt: index, in: lines)
    }

    /// File names already listed in the block, continuation backslashes stripped.
    static func tokens(in lines: [String], block: ClosedRange<Int>) -> [String] {
        let content = block
            .map { lines[$0].hasSuffix("\\") ? String(lines[$0].dropLast()) : lines[$0] }
            .joined(separator: " ")
        let words = content.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return Array(words.dropFirst())
    }

    /// Where to insert a brand new `patchfiles` line when none exists: right
    /// after the last checksums/distfiles/master_sites block, else right before
    /// the first configure/build/variant stanza, else at the end of the file.
    static func insertionIndex(in lines: [String]) -> Int {
        var lastBlockEnd: Int?
        var index = 0
        while index < lines.count {
            guard let word = directiveWord(lines[index]) else {
                index += 1
                continue
            }
            if checksumDirectives.contains(word) {
                let range = blockRange(startingAt: index, in: lines)
                lastBlockEnd = range.upperBound
                index = range.upperBound + 1
            } else {
                index += 1
            }
        }
        if let lastBlockEnd { return lastBlockEnd + 1 }

        for (index, line) in lines.enumerated() {
            if let word = directiveWord(line), stanzaFallbackDirectives.contains(word) { return index }
        }
        return lines.last == "" ? lines.count - 1 : lines.count
    }

    /// Inserts `line`, keeping a trailing newline (an empty final element) last.
    static func insert(_ line: String, at index: Int, into lines: inout [String]) {
        let limit = lines.last == "" ? lines.count - 1 : lines.count
        lines.insert(line, at: min(index, limit))
    }

    /// The first whitespace-delimited token of a line, trimmed. `nil` when blank.
    private static func directiveWord(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let separator = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return trimmed }
        return String(trimmed[trimmed.startIndex..<separator])
    }

    private static func blockRange(startingAt index: Int, in lines: [String]) -> ClosedRange<Int> {
        var end = index
        while end < lines.count - 1, lines[end].hasSuffix("\\") {
            end += 1
        }
        return index...end
    }
}
