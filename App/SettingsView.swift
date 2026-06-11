import SwiftUI
import OmniPreviewCore

struct SettingsView: View {
    var body: some View {
        TabView {
            LicenseSettingsView()
                .tabItem { Label("License", systemImage: "key.fill") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            PluginSettingsView()
                .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 480)
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
    var body: some View {
        Form {
            Section {
                ForEach(RendererRegistry.all, id: \.idString) { renderer in
                    Text(type(of: renderer).displayName)
                }
            } footer: {
                Text("Renderer list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

extension PreviewRenderer {
    var idString: String { type(of: self).id }
}
