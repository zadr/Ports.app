import Foundation

// macports.conf lines are `key<whitespace>value`, `#` comments, or blank.
// A comment line is a commented-out setting when the character right after
// `#` is not whitespace and starts an identifier; otherwise it is prose
// documentation. This matches how the shipped file distinguishes
// `#macportsuser        z` (a setting) from `# User to run operations as...`
// (a doc line).
enum MacPortsConfigParsing {
    static func parseSettings(_ text: String) -> [ConfigurationSetting] {
        let lines = TextLines.split(text).lines
        var docBuffer: [String] = []
        var results: [ConfigurationSetting] = []
        var indexByKey: [String: Int] = [:]

        func flushDocumentation() -> String {
            defer { docBuffer = [] }
            var block = docBuffer
            while block.first == "" { block.removeFirst() }
            while block.last == "" { block.removeLast() }
            return block.joined(separator: "\n")
        }

        func record(key: String, value: String, isCommentedOut: Bool, lineIndex: Int) {
            let setting = ConfigurationSetting(
                key: key,
                value: value,
                documentation: flushDocumentation(),
                isCommentedOut: isCommentedOut,
                lineIndex: lineIndex
            )
            if let existing = indexByKey[key] {
                results[existing] = setting
            } else {
                indexByKey[key] = results.count
                results.append(setting)
            }
        }

        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                docBuffer = []
                continue
            }
            if line.hasPrefix("#") {
                let body = line.dropFirst()
                if body.isEmpty {
                    docBuffer.append("")
                    continue
                }
                if body.first!.isWhitespace {
                    var stripped = String(body)
                    if stripped.first == " " { stripped.removeFirst() }
                    docBuffer.append(stripped)
                    continue
                }
                if let (key, value) = splitKeyValue(String(body)) {
                    record(key: key, value: value, isCommentedOut: true, lineIndex: index)
                } else {
                    docBuffer.append(String(body))
                }
                continue
            }
            if let (key, value) = splitKeyValue(line) {
                record(key: key, value: value, isCommentedOut: false, lineIndex: index)
            }
        }
        return results.sorted { $0.lineIndex < $1.lineIndex }
    }

    /// Splits `key<whitespace>value`. Returns nil when the line does not
    /// start with a plausible identifier, so stray text is left as prose.
    static func splitKeyValue(_ line: String) -> (key: String, value: String)? {
        guard let separatorStart = line.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let key = String(line[line.startIndex..<separatorStart])
        guard isValidKey(key) else { return nil }
        let afterKey = line[separatorStart...]
        guard let valueStart = afterKey.firstIndex(where: { !$0.isWhitespace }) else {
            return (key, "")
        }
        let value = String(afterKey[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Applies `defaults`'s values and, where the live file had no doc block
    /// of its own, its documentation, onto `settings` (matched by key).
    static func applyingDefaults(_ defaults: String, to settings: [ConfigurationSetting]) -> [ConfigurationSetting] {
        let defaultSettings = parseSettings(defaults)
        let byKey = Dictionary(uniqueKeysWithValues: defaultSettings.map { ($0.key, $0) })
        return settings.map { setting in
            guard let match = byKey[setting.key] else { return setting }
            var updated = setting
            updated.defaultValue = match.value
            if updated.documentation.isEmpty { updated.documentation = match.documentation }
            return updated
        }
    }

    /// Rewrites the single line for `key` to `value`, preserving the
    /// key/value separator (and thus column alignment) already on that line.
    /// Uncomments a commented-out line in place; appends a new line when the
    /// key is entirely absent.
    static func settingValue(_ value: String, for key: String, in configuration: MacPortsConfiguration) -> String {
        var (lines, trailingNewline) = TextLines.split(configuration.text)
        guard let setting = configuration.setting(key) else {
            if !lines.isEmpty { lines.append("") }
            lines.append("# Added by Ports.")
            lines.append("\(key)\t\(value)")
            return TextLines.join(lines, trailingNewline: trailingNewline)
        }
        var line = lines[setting.lineIndex]
        if setting.isCommentedOut {
            precondition(line.hasPrefix("#"))
            line.removeFirst()
        }
        lines[setting.lineIndex] = rewritingValue(of: line, key: key, to: value)
        return TextLines.join(lines, trailingNewline: trailingNewline)
    }

    /// Comments the line for `key` out in place. A no-op when the key is
    /// absent or already commented out.
    static func clearingValue(for key: String, in configuration: MacPortsConfiguration) -> String {
        guard let setting = configuration.setting(key), !setting.isCommentedOut else {
            return configuration.text
        }
        var (lines, trailingNewline) = TextLines.split(configuration.text)
        lines[setting.lineIndex] = "#" + lines[setting.lineIndex]
        return TextLines.join(lines, trailingNewline: trailingNewline)
    }

    private static func rewritingValue(of line: String, key: String, to value: String) -> String {
        guard let separatorStart = line.firstIndex(where: { $0.isWhitespace }) else {
            return "\(key)\t\(value)"
        }
        let afterKey = line[separatorStart...]
        let valueStart = afterKey.firstIndex(where: { !$0.isWhitespace }) ?? afterKey.endIndex
        let separator = afterKey[afterKey.startIndex..<valueStart]
        return String(line[line.startIndex..<separatorStart]) + separator + value
    }
}
