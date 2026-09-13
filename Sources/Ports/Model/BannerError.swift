import Foundation

/// Wraps an error's localized description for display as a dismissible banner or alert.
struct BannerError: Identifiable {
    let id = UUID()
    var message: String

    init(_ error: any Error) {
        message = error.localizedDescription
    }

    init(message: String) {
        self.message = message
    }
}
