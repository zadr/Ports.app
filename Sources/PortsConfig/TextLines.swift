import Foundation

/// Line splitting that round-trips a trailing newline instead of losing it,
/// so single-line edits never change whether the file ends with one.
enum TextLines {
    static func split(_ text: String) -> (lines: [String], trailingNewline: Bool) {
        var lines = text.components(separatedBy: "\n")
        let trailingNewline = lines.last == ""
        if trailingNewline { lines.removeLast() }
        return (lines, trailingNewline)
    }

    static func join(_ lines: [String], trailingNewline: Bool) -> String {
        lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }
}
