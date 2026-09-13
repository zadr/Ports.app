import Foundation

// sources.conf lines are a URL, optional `[flags]`, or a `#` comment. A
// disabled source is a comment line whose remainder (after stripping `#` and
// leading whitespace) still parses as a URL line; other comment lines are
// header prose and are kept verbatim by `applying`.
enum SourcesConfigParsing {
    static func parse(_ text: String, path: String) -> SourcesConfiguration {
        let lines = TextLines.split(text).lines
        var sources: [PortSource] = []
        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                let candidate = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let parsed = parseEntry(candidate) {
                    sources.append(
                        PortSource(url: parsed.url, flags: parsed.flags, isEnabled: false, lineIndex: index)
                    )
                }
            } else if let parsed = parseEntry(trimmed) {
                sources.append(
                    PortSource(url: parsed.url, flags: parsed.flags, isEnabled: true, lineIndex: index)
                )
            }
        }
        return SourcesConfiguration(path: path, text: text, sources: sources)
    }

    static func applying(_ sources: [PortSource], to configuration: SourcesConfiguration) -> String {
        let (originalLines, trailingNewline) = TextLines.split(configuration.text)
        let sourceLineIndices = Set(configuration.sources.map(\.lineIndex))
        var kept: [String] = []
        var insertionIndex: Int?
        for (index, line) in originalLines.enumerated() {
            if sourceLineIndices.contains(index) {
                if insertionIndex == nil { insertionIndex = kept.count }
                continue
            }
            kept.append(line)
        }
        kept.insert(contentsOf: sources.map(render), at: insertionIndex ?? kept.count)
        return TextLines.join(kept, trailingNewline: trailingNewline)
    }

    static func validate(_ sources: [PortSource]) -> [String] {
        var problems: [String] = []

        let activeDefaults = sources.filter { $0.isEnabled && $0.isDefault }
        if activeDefaults.isEmpty {
            problems.append("No source is flagged as the default.")
        } else if activeDefaults.count > 1 {
            problems.append("More than one source is flagged as the default.")
        }

        if let defaultIndex = sources.firstIndex(where: { $0.isEnabled && $0.isDefault }),
            !sources[defaultIndex].isLocal
        {
            for source in sources[(defaultIndex + 1)...] where source.isEnabled && source.isLocal {
                problems.append(
                    "Local source \(source.url) is listed after the default remote source; its Portfiles will never take precedence."
                )
            }
        }

        for source in sources where source.isEnabled && source.url.hasPrefix("file://") {
            guard let path = source.localPath, !FileManager.default.fileExists(atPath: path) else { continue }
            problems.append("Local source path does not exist: \(path)")
        }

        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for source in sources {
            if !seen.insert(source.url).inserted { duplicates.insert(source.url) }
        }
        for url in duplicates.sorted() {
            problems.append("Source is listed more than once: \(url)")
        }

        return problems
    }

    private static func render(_ source: PortSource) -> String {
        var line = source.url
        if !source.flags.isEmpty { line += " [\(source.flags.joined(separator: ","))]" }
        return source.isEnabled ? line : "#" + line
    }

    private static func parseEntry(_ text: String) -> (url: String, flags: [String])? {
        guard let bracketStart = text.firstIndex(of: "["), text.hasSuffix("]") else {
            return isURLLike(text) ? (text, []) : nil
        }
        let url = text[text.startIndex..<bracketStart].trimmingCharacters(in: .whitespaces)
        guard isURLLike(url) else { return nil }
        let flagsText = text[text.index(after: bracketStart)..<text.index(before: text.endIndex)]
        let flags = flagsText
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        return (url, flags)
    }

    private static func isURLLike(_ text: String) -> Bool {
        !text.isEmpty && (text.contains("://") || text.hasPrefix("/"))
    }
}
