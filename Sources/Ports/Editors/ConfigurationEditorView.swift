import PortsConfig
import SwiftUI

struct ConfigurationEditorView: View {
    @Environment(PortsModel.self) private var model
    @State private var mode: Mode = .structured

    enum Mode: String, CaseIterable, Identifiable {
        case structured = "Settings"
        case raw = "Raw File"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if let configuration = model.configuration {
                switch mode {
                case .structured:
                    SettingsListView(configuration: configuration)
                case .raw:
                    RawConfigEditor(path: configuration.path, text: configuration.text, onSave: save)
                        .id(configuration.text)
                }
            } else {
                ContentUnavailableView("No Configuration Loaded", systemImage: "gearshape")
            }
        }
        .navigationTitle("Configuration")
    }

    private func save(_ text: String) async {
        guard let configuration = model.configuration else { return }
        do {
            try await configuration.save(text)
            model.loadConfigurations()
        } catch {
            model.banner = BannerError(error)
        }
    }
}
