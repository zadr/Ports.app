import Foundation

enum SidebarSection: Hashable, Identifiable {
    case installed
    case updates
    case requested
    case inactive
    case customized
    case search
    case sources
    case configuration
    case globalVariants

    var id: Self { self }

    var title: String {
        switch self {
        case .installed: "Installed"
        case .updates: "Updates"
        case .requested: "Requested"
        case .inactive: "Inactive"
        case .customized: "Customized"
        case .search: "Search"
        case .sources: "Sources"
        case .configuration: "Configuration"
        case .globalVariants: "Global Variants"
        }
    }

    /// Setup sections are a single editor, so they drop the list column.
    var usesContentColumn: Bool {
        switch self {
        case .sources, .configuration, .globalVariants: false
        default: true
        }
    }

    var systemImage: String {
        switch self {
        case .installed: "square.stack.3d.up"
        case .updates: "arrow.triangle.2.circlepath"
        case .requested: "checkmark.circle"
        case .inactive: "moon.zzz"
        case .customized: "pencil.and.outline"
        case .search: "magnifyingglass"
        case .sources: "tray.full"
        case .configuration: "gearshape"
        case .globalVariants: "slider.horizontal.3"
        }
    }
}
