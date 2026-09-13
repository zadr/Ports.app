import PortsConfig
import SwiftUI

struct SettingsListView: View {
    let configuration: MacPortsConfiguration

    @Environment(PortsModel.self) private var model

    var body: some View {
        List(configuration.settings) { setting in
            SettingRow(setting: setting, onSetValue: setValue, onEnable: enable, onReset: reset)
        }
    }

    private func apply(_ text: String) {
        guard let current = model.configuration else { return }
        Task {
            do {
                try await current.save(text)
                model.loadConfigurations()
            } catch {
                model.banner = BannerError(error)
            }
        }
    }

    private func setValue(_ value: String, for key: String) {
        guard let current = model.configuration else { return }
        apply(current.settingValue(value, for: key))
    }

    private func enable(_ key: String, defaultValue: String) {
        setValue(defaultValue, for: key)
    }

    private func reset(_ key: String) {
        guard let current = model.configuration else { return }
        apply(current.clearingValue(for: key))
    }
}

private struct SettingRow: View {
    let setting: ConfigurationSetting
    let onSetValue: (String, String) -> Void
    let onEnable: (String, String) -> Void
    let onReset: (String) -> Void

    @State private var value: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(setting.key).font(.body.monospaced())
                if setting.isModified {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.blue)
                        .help("Differs from default")
                }
                Spacer()
                if setting.isCommentedOut {
                    Button("Enable") { onEnable(setting.key, setting.defaultValue ?? "") }
                } else {
                    Button("Reset") { onReset(setting.key) }
                }
            }
            if !setting.documentation.isEmpty {
                Text(setting.documentation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Value", text: $value)
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .disabled(setting.isCommentedOut)
                .onSubmit(commit)
        }
        .padding(.vertical, 2)
        .task(id: setting.value) { value = setting.value }
    }

    private func commit() {
        guard value != setting.value else { return }
        onSetValue(value, setting.key)
    }
}
