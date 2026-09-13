import CryptoKit
import Foundation

/// Baseline storage: a pristine copy of a fork's upstream Portfile (plus its
/// `files` directory) kept outside the tree, so edits and `revert` always have
/// something stable to compare against or restore from.
extension OverlayManager {
    static func baselinesRoot() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Ports/baselines", directoryHint: .isDirectory).path(percentEncoded: false)
    }

    /// First 16 hex characters of the tree path's SHA-256, so two configured
    /// trees never collide on the same baseline directory.
    static func treeIdentifier(_ treePath: String) -> String {
        let digest = SHA256.hash(data: Data(treePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    static func baselineDirectory(treePath: String, category: String, name: String) -> String {
        "\(baselinesRoot())/\(treeIdentifier(treePath))/\(category)/\(name)"
    }

    static func baselinePortfilePath(treePath: String, category: String, name: String) -> String {
        "\(baselineDirectory(treePath: treePath, category: category, name: name))/Portfile"
    }
}

extension PortfileFork {
    var baselineDirectory: String {
        OverlayManager.baselineDirectory(treePath: treePath, category: category, name: name)
    }

    var baselinePortfilePath: String { "\(baselineDirectory)/Portfile" }
}
