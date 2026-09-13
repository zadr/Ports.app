import Foundation

/// Parses `port -q installed`: `  name @1.2.3_0+variant (active)`.
func parseInstalledPorts(_ text: String) -> [InstalledPort] {
    var results: [InstalledPort] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, fields[1].hasPrefix("@") else { continue }
        let name = String(fields[0])
        let token = fields[1].dropFirst()
        let (version, revision, variants) = parseVersionToken(token)
        results.append(
            InstalledPort(
                name: name,
                version: version,
                revision: revision,
                variants: variants,
                isActive: line.contains("(active)"),
                isRequested: false
            )
        )
    }
    return results
}

/// Parses `port -q outdated`: `name  1.2_0 < 1.3_0  (note)`.
func parseOutdatedPorts(_ text: String) -> [OutdatedPort] {
    var results: [OutdatedPort] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let fields = rawLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 4 else { continue }
        let note = fields.count > 4 ? fields[4...].joined(separator: " ") : nil
        results.append(
            OutdatedPort(
                name: fields[0],
                installedVersion: fields[1],
                availableVersion: fields[3],
                note: (note?.isEmpty == false) ? note : nil
            )
        )
    }
    return results
}

/// Parses tab separated `port search --line --name --version --categories --description`.
func parseSearchResults(_ text: String) -> [PortSearchResult] {
    var results: [PortSearchResult] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let fields = String(rawLine).components(separatedBy: "\t")
        guard !fields.isEmpty, !fields[0].isEmpty else { continue }
        func field(_ index: Int) -> String { index < fields.count ? fields[index] : "" }
        let categories = field(2).split(separator: " ").map(String.init)
        results.append(
            PortSearchResult(name: field(0), version: field(1), categories: categories, summary: field(3))
        )
    }
    return results
}

/// Parses tab separated `port info --line` with the field order used by `PortClient.info`.
func parsePortInfo(_ text: String) -> PortInfo? {
    guard let rawLine = text.split(separator: "\n", omittingEmptySubsequences: true).first else { return nil }
    let fields = String(rawLine).components(separatedBy: "\t")
    guard !fields.isEmpty, !fields[0].isEmpty else { return nil }
    func field(_ index: Int) -> String { index < fields.count ? fields[index] : "" }
    return PortInfo(
        name: field(0),
        version: field(1),
        revision: Int(field(2)) ?? 0,
        categories: field(4).split(separator: " ").map(String.init),
        maintainers: field(9).split(separator: " ").map(String.init),
        summary: field(6),
        details: field(7),
        homepage: field(5),
        license: field(8),
        variantNames: field(3).split(separator: " ").map(String.init)
    )
}

/// Parses `port -q variants`: `   name: summary`, `[+]name: summary`.
func parsePortVariants(_ text: String) -> [PortVariant] {
    var results: [PortVariant] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        var line = String(rawLine)
        var isSelected = false
        let prefix = line.prefix(3)
        if prefix == "[+]" || prefix == "[-]" {
            isSelected = prefix == "[+]"
            line.removeFirst(3)
        }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        guard let colonIndex = line.firstIndex(of: ":") else {
            results.append(PortVariant(name: line, summary: "", isSelected: isSelected))
            continue
        }
        let name = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
        let summary = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
        results.append(PortVariant(name: name, summary: summary, isSelected: isSelected))
    }
    return results
}

/// Parses `port -q deps`: `Library Dependencies: a, b, c`.
func parsePortDependencies(_ text: String) -> PortDependencies {
    var library: [String] = []
    var build: [String] = []
    var runtime: [String] = []
    var extract: [String] = []
    var fetch: [String] = []
    var test: [String] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let colonIndex = rawLine.firstIndex(of: ":") else { continue }
        let label = rawLine[rawLine.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
        let values = rawLine[rawLine.index(after: colonIndex)...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch label {
        case "Library Dependencies": library = values
        case "Build Dependencies": build = values
        case "Runtime Dependencies": runtime = values
        case "Extract Dependencies": extract = values
        case "Fetch Dependencies": fetch = values
        case "Test Dependencies": test = values
        default: break
        }
    }
    return PortDependencies(
        library: library, build: build, runtime: runtime, extract: extract, fetch: fetch, test: test
    )
}

/// Parses `port -q space`: `647.02 KiB name` into bytes.
func parseDiskUsage(_ text: String) -> Int64 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true)
    guard fields.count >= 2, let value = Double(fields[0]) else { return 0 }
    let multiplier: Double
    switch fields[1] {
    case "B": multiplier = 1
    case "KiB": multiplier = 1024
    case "MiB": multiplier = 1024 * 1024
    case "GiB": multiplier = 1024 * 1024 * 1024
    default: multiplier = 1
    }
    return Int64((value * multiplier).rounded())
}

/// Splits the token following `@` in a `port -q installed` row, e.g. `1.18.4_2+quartz+x11`,
/// into version, revision, and variant tokens (each keeping its `+`/`-` sign).
private func parseVersionToken(_ token: Substring) -> (version: String, revision: Int, variants: [String]) {
    let signIndex = token.firstIndex { $0 == "+" || $0 == "-" }
    let base = signIndex.map { token[token.startIndex..<$0] } ?? token
    let variantsPart = signIndex.map { token[$0...] } ?? Substring("")
    let variants = splitVariantTokens(variantsPart)

    guard let underscoreIndex = base.lastIndex(of: "_") else {
        return (String(base), 0, variants)
    }
    let version = String(base[base.startIndex..<underscoreIndex])
    let revision = Int(base[base.index(after: underscoreIndex)...]) ?? 0
    return (version, revision, variants)
}

private func splitVariantTokens(_ text: Substring) -> [String] {
    guard !text.isEmpty else { return [] }
    var tokens: [String] = []
    var current = ""
    for character in text {
        if character == "+" || character == "-" {
            if !current.isEmpty { tokens.append(current) }
            current = String(character)
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
