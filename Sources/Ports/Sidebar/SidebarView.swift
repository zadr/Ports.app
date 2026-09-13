import SwiftUI

struct SidebarView: View {
    @Environment(PortsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedSection) {
            Section("Library") {
                row(.installed)
                row(.updates, badge: model.outdated.count)
                row(.requested)
                row(.inactive)
                row(.customized, badge: model.customizedCount)
            }
            Section("Discover") {
                row(.search)
            }
            Section("Setup") {
                row(.sources)
                row(.configuration)
                row(.globalVariants)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            EnvironmentStatusView()
        }
    }

    private func row(_ section: SidebarSection, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(badge)
            .tag(section)
    }
}
