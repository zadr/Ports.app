import AppKit
import SwiftUI

/// The columns appear only after MacPorts detection finishes, and a split view
/// built after that first layout pass never applies its autosaved frames, so the
/// content column width is stored and reapplied here.
///
/// Measured against the AppKit hierarchy SwiftUI builds: the panes are the split
/// view's `arrangedSubviews`, which sit among unrelated `subviews`; a pane's
/// frame is measured from the split view's origin, so its width is the distance
/// from the end of the pane before it.
struct ColumnWidthMemory: NSViewRepresentable {
    static let contentKey = "ports.columnWidth.content"

    let key: String

    func makeCoordinator() -> Coordinator {
        Coordinator(key: key)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(from: view)
    }

    @MainActor
    final class Coordinator {
        private let key: String
        private weak var splitView: NSSplitView?
        private weak var pane: NSView?
        // Touched by deinit, which cannot be actor isolated.
        private nonisolated(unsafe) var observer: (any NSObjectProtocol)?
        private var isRestoring = false
        private var isAttaching = false

        init(key: String) {
            self.key = key
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(from view: NSView) {
            guard splitView == nil, !isAttaching else { return }
            isAttaching = true
            Task { @MainActor in
                defer { isAttaching = false }
                for _ in 0..<40 {
                    if bind(from: view) { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                restore()
                observe()
            }
        }

        private func bind(from view: NSView) -> Bool {
            var candidate: NSView = view
            while let parent = candidate.superview {
                if let split = parent as? NSSplitView {
                    guard split.arrangedSubviews.contains(candidate) else { return false }
                    splitView = split
                    pane = candidate
                    return true
                }
                candidate = parent
            }
            return false
        }

        private var index: Int? {
            guard let splitView, let pane else { return nil }
            return splitView.arrangedSubviews.firstIndex(of: pane)
        }

        /// Width of everything to the left of this pane.
        private var leadingWidth: CGFloat? {
            guard let splitView, let index, index > 0 else { return nil }
            return splitView.arrangedSubviews[index - 1].frame.maxX
        }

        private func restore() {
            guard let splitView, let index, let leadingWidth,
                  let stored = Self.storedWidth(key)
            else { return }
            isRestoring = true
            splitView.setPosition(leadingWidth + stored, ofDividerAt: index)
            isRestoring = false
        }

        private func observe() {
            guard observer == nil, let splitView else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
        }

        private func save() {
            guard !isRestoring, let pane, let leadingWidth else { return }
            let width = pane.frame.maxX - leadingWidth
            guard width > 1 else { return }
            UserDefaults.standard.set(width, forKey: key)
        }

        static func storedWidth(_ key: String) -> CGFloat? {
            let value = UserDefaults.standard.double(forKey: key)
            return value > 0 ? value : nil
        }
    }
}

extension View {
    func remembersColumnWidth(_ key: String) -> some View {
        background(ColumnWidthMemory(key: key))
    }
}
