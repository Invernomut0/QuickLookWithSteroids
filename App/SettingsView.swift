import SwiftUI
import OmniPreviewCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            PluginSettingsView()
                .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 440)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)

            LabeledContent("Quick Look") {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Open Extension Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                    }
                    Text("Enable both OmniPreview extensions under Quick Look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Cache") {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Clear Preview Cache") {
                        PreviewPipeline.shared.clearCache()
                    }
                    Text("In-memory cache of rendered previews.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct PluginSettingsView: View {
    // Local mirror so toggles refresh immediately; persistence lives in
    // RendererSettings (UserDefaults).
    @State private var enabled: [String: Bool] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(RendererRegistry.all, id: \.idString) { renderer in
                    Toggle(type(of: renderer).displayName, isOn: binding(for: type(of: renderer).id))
                }
            } footer: {
                Text("Disabled renderers are skipped when generating previews in this app. The Quick Look extensions currently keep their own settings; shared settings require an App Group (planned).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear {
            for renderer in RendererRegistry.all {
                let id = type(of: renderer).id
                enabled[id] = RendererSettings.isEnabled(id: id)
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabled[id] ?? true },
            set: { value in
                enabled[id] = value
                RendererSettings.setEnabled(id: id, value)
            }
        )
    }
}

extension PreviewRenderer {
    var idString: String { type(of: self).id }
}
