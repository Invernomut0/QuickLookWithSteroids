import SwiftUI
import OmniPreviewCore
import OmniPreviewUI

@main
struct OmniPreviewApp: App {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup(id: "tester") {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }

        MenuBarExtra("OmniPreview", systemImage: "eye", isInserted: $showMenuBarIcon) {
            MenuBarMenu()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Preview Tester") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "tester")
        }

        Divider()

        SettingsButton()

        Button("Quick Look Extensions…") {
            // System Settings pane where the user enables the extensions.
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
        }

        Divider()

        Button("About OmniPreview") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Rich Quick Look previews for archives, ML models, databases, certificates, and more.",
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                ),
            ])
        }

        Divider()

        Button("Quit OmniPreview") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// `SettingsLink` exists only on macOS 14+; fall back to the legacy
/// selector on macOS 13.
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}

struct ContentView: View {
    @State private var previewedDocument: PreviewDocument?
    @State private var previewError: String?

    var body: some View {
        Group {
            if let document = previewedDocument {
                PreviewDocumentView(document: document)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("OmniPreview")
                        .font(.title2.weight(.semibold))
                    Text("Drop a file here to test rendering.\nQuick Look extensions are active once this app has been launched.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let previewError {
                        Text(previewError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            if previewedDocument != nil {
                Button("Clear") { previewedDocument = nil }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    do {
                        previewedDocument = try await PreviewPipeline.shared.document(for: url)
                        previewError = nil
                    } catch {
                        previewedDocument = nil
                        previewError = error.localizedDescription
                    }
                }
            }
            return true
        }
    }
}
