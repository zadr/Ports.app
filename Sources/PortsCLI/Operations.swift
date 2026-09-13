func operationTitle(_ operation: PortOperation) -> String {
    switch operation {
    case .install(let name, _): "Install \(name)"
    case .uninstall(let name, let version):
        version.map { "Uninstall \(name) @\($0)" } ?? "Uninstall \(name)"
    case .upgrade(let names): names.isEmpty ? "Upgrade" : "Upgrade \(names.joined(separator: ", "))"
    case .upgradeOutdated: "Upgrade Outdated Ports"
    case .activate(let name, let version):
        version.map { "Activate \(name) @\($0)" } ?? "Activate \(name)"
    case .deactivate(let name): "Deactivate \(name)"
    case .clean(let name): "Clean \(name)"
    case .selfupdate: "Self Update"
    case .sync: "Sync Port Definitions"
    case .reclaim: "Reclaim Disk Space"
    case .reindex(let directory): "Reindex \(directory)"
    case .custom(let arguments): "Run port \(arguments.joined(separator: " "))"
    }
}

/// False for read-only actions and for `reindex`, which writes only the tree.
func operationWritesPrefix(_ operation: PortOperation) -> Bool {
    switch operation {
    case .reindex, .custom: false
    default: true
    }
}

/// Argument vector the operation runs, exposed so the UI can show the exact command.
func portOperationArguments(_ operation: PortOperation) -> [String] {
    switch operation {
    case .install(let name, let variants): ["-N", "install", name] + variants
    case .uninstall(let name, let version):
        version.map { ["-N", "uninstall", name, "@\($0)"] } ?? ["-N", "uninstall", name]
    case .upgrade(let names): ["-N", "upgrade"] + names
    case .upgradeOutdated: ["-N", "upgrade", "outdated"]
    case .activate(let name, let version):
        version.map { ["-N", "activate", name, "@\($0)"] } ?? ["-N", "activate", name]
    case .deactivate(let name): ["-N", "deactivate", name]
    case .clean(let name): ["-N", "clean", "--all", name]
    case .selfupdate: ["-N", "selfupdate"]
    case .sync: ["-N", "sync"]
    case .reclaim: ["-N", "reclaim"]
    case .reindex: []
    case .custom(let arguments): arguments
    }
}
