import SwiftUI

struct RootView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.startupState {
            case .loading:
                ProgressView("Detecting MacPorts")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .portMissing:
                PortMissingView()
            case .ready:
                mainSplitView
            }
        }
        .task { await model.bootstrap() }
        .sheet(item: $model.editingFork) { fork in
            PortfileEditorView(fork: fork)
        }
        .alert("Error", isPresented: isBannerPresented, presenting: model.banner) { _ in
            Button("OK", role: .cancel) {}
        } message: { banner in
            Text(banner.message)
        }
    }

    private var isBannerPresented: Binding<Bool> {
        Binding(
            get: { model.banner != nil },
            set: { if !$0 { model.banner = nil } }
        )
    }

    private var mainSplitView: some View {
        VStack(spacing: 0) {
            if model.selectedSection.usesContentColumn {
                NavigationSplitView {
                    SidebarView()
                } content: {
                    ContentColumnView()
                        .remembersColumnWidth(ColumnWidthMemory.contentKey)
                } detail: {
                    DetailColumnView()
                }
            } else {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    DetailColumnView()
                }
            }
            OperationConsoleView()
        }
        .frame(minWidth: 860, minHeight: 560)
    }
}
