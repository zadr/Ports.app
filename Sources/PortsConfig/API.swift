import Foundation
import PortsShell

// MARK: - macports.conf

public struct ConfigurationSetting: Sendable, Hashable, Identifiable {
    public var key: String
    public var value: String
    /// Comment block that precedes the key in the file, comment markers stripped.
    public var documentation: String
    /// True when the only occurrence of the key is inside a comment.
    public var isCommentedOut: Bool
    public var lineIndex: Int
    /// Value in macports.conf.default, when the key appears there.
    public var defaultValue: String?

    public init(
        key: String,
        value: String,
        documentation: String = "",
        isCommentedOut: Bool = false,
        lineIndex: Int = 0,
        defaultValue: String? = nil
    ) {
        self.key = key
        self.value = value
        self.documentation = documentation
        self.isCommentedOut = isCommentedOut
        self.lineIndex = lineIndex
        self.defaultValue = defaultValue
    }

    public var id: String { key }
    public var isModified: Bool { defaultValue.map { $0 != value } ?? false }
}

/// Line-preserving view of macports.conf. Edits rewrite single lines so
/// comments, ordering and whitespace in the rest of the file survive.
public struct MacPortsConfiguration: Sendable, Hashable {
    public var path: String
    public var text: String
    public var settings: [ConfigurationSetting]

    public init(path: String, text: String, settings: [ConfigurationSetting]) {
        self.path = path
        self.text = text
        self.settings = settings
    }

    public static func load(path: String) throws -> MacPortsConfiguration {
        let text: String
        do { text = try PrivilegedFile.read(path) } catch { throw ConfigurationError.unreadable(path: path) }
        let defaults = try? PrivilegedFile.read(path + ".default")
        return parse(text: text, path: path, defaults: defaults)
    }

    /// `defaults` supplies documentation and default values, normally parsed
    /// from the `macports.conf.default` beside `path`.
    public static func parse(
        text: String,
        path: String,
        defaults: String? = nil
    ) -> MacPortsConfiguration {
        var settings = MacPortsConfigParsing.parseSettings(text)
        if let defaults {
            settings = MacPortsConfigParsing.applyingDefaults(defaults, to: settings)
        }
        return MacPortsConfiguration(path: path, text: text, settings: settings)
    }

    public func setting(_ key: String) -> ConfigurationSetting? { settings.first { $0.key == key } }
    public func value(for key: String) -> String? {
        guard let setting = setting(key) else { return nil }
        return setting.isCommentedOut ? setting.defaultValue : setting.value
    }

    /// File text with `key` set to `value`. Uncomments a commented key in place
    /// and appends the key when it is absent.
    public func settingValue(_ value: String, for key: String) -> String {
        MacPortsConfigParsing.settingValue(value, for: key, in: self)
    }
    /// File text with `key` commented out, restoring its default behaviour.
    public func clearingValue(for key: String) -> String {
        MacPortsConfigParsing.clearingValue(for: key, in: self)
    }

    public func save(_ text: String) async throws { try await PrivilegedFile.write(text, to: path) }
}

// MARK: - sources.conf

public struct PortSource: Sendable, Hashable, Identifiable {
    public var url: String
    /// Bracketed flags on the line, without brackets: `default`, `nosync`.
    public var flags: [String]
    public var isEnabled: Bool
    public var lineIndex: Int

    public init(url: String, flags: [String] = [], isEnabled: Bool = true, lineIndex: Int = 0) {
        self.url = url
        self.flags = flags
        self.isEnabled = isEnabled
        self.lineIndex = lineIndex
    }

    public var id: String { url }
    public var isDefault: Bool { flags.contains("default") }
    public var isSynchronized: Bool { !flags.contains("nosync") }
    public var isLocal: Bool { url.hasPrefix("file://") || url.hasPrefix("/") }
    /// Filesystem path for a local tree, percent decoding applied.
    public var localPath: String? {
        if url.hasPrefix("file://") {
            let raw = String(url.dropFirst("file://".count))
            return raw.removingPercentEncoding ?? raw
        }
        if url.hasPrefix("/") { return url.removingPercentEncoding ?? url }
        return nil
    }

    public var displayName: String {
        if let localPath {
            return localPath.split(separator: "/").last.map(String.init) ?? localPath
        }
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let components = parsed.path.split(separator: "/").map(String.init)
        guard let last = components.last else { return host }
        return components.count > 1 ? "\(host)/…/\(last)" : "\(host)/\(last)"
    }
}

public struct SourcesConfiguration: Sendable, Hashable {
    public var path: String
    public var text: String
    public var sources: [PortSource]

    public init(path: String, text: String, sources: [PortSource]) {
        self.path = path
        self.text = text
        self.sources = sources
    }

    public static func load(path: String) throws -> SourcesConfiguration {
        let text: String
        do { text = try PrivilegedFile.read(path) } catch { throw ConfigurationError.unreadable(path: path) }
        return parse(text: text, path: path)
    }

    public static func parse(text: String, path: String) -> SourcesConfiguration {
        SourcesConfigParsing.parse(text, path: path)
    }

    /// File text rewritten so the source lines match `sources` in order.
    /// Leading comment lines that are not source entries are kept.
    public func applying(_ sources: [PortSource]) -> String {
        SourcesConfigParsing.applying(sources, to: self)
    }

    public func save(_ text: String) async throws { try await PrivilegedFile.write(text, to: path) }

    /// Local trees come first so their Portfiles win over the rsync tree; the
    /// `default` flag must stay on exactly one entry. Returns problems found.
    public func validate(_ sources: [PortSource]) -> [String] {
        SourcesConfigParsing.validate(sources)
    }
}

// MARK: - variants.conf

/// Global variants applied to every port, one `+name` or `-name` per entry.
public struct VariantsConfiguration: Sendable, Hashable {
    public var path: String
    public var text: String
    public var variants: [String]

    public init(path: String, text: String, variants: [String]) {
        self.path = path
        self.text = text
        self.variants = variants
    }

    public static func load(path: String) throws -> VariantsConfiguration {
        let text: String
        do { text = try PrivilegedFile.read(path) } catch { throw ConfigurationError.unreadable(path: path) }
        return parse(text: text, path: path)
    }

    public static func parse(text: String, path: String) -> VariantsConfiguration {
        VariantsConfiguration(path: path, text: text, variants: VariantsConfigParsing.parse(text))
    }

    public func applying(_ variants: [String]) -> String {
        VariantsConfigParsing.applying(variants, to: text)
    }

    public func save(_ text: String) async throws { try await PrivilegedFile.write(text, to: path) }
}

public enum ConfigurationError: Error, Sendable, Hashable {
    case unreadable(path: String)
    case invalidValue(key: String, reason: String)
}
