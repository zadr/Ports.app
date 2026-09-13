import Foundation

// variants.conf tokens are whitespace- or newline-separated `+name`/`-name`
// entries; `#` starts a comment that runs to end of line.
enum VariantsConfigParsing {
    static func parse(_ text: String) -> [String] {
        TextLines.split(text).lines.flatMap { line -> [String] in
            let active = line.firstIndex(of: "#").map { String(line[line.startIndex..<$0]) } ?? line
            return tokens(in: active)
        }
    }

    static func applying(_ variants: [String], to text: String) -> String {
        let (lines, trailingNewline) = TextLines.split(text)
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("#")
        }
        var result = kept
        if !result.isEmpty, result.last?.isEmpty == false { result.append("") }
        result.append(contentsOf: variants)
        return TextLines.join(result, trailingNewline: trailingNewline)
    }

    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0.hasPrefix("+") || $0.hasPrefix("-") }
    }
}
