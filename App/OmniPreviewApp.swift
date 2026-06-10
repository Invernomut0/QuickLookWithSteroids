import SwiftUI
import OmniPreviewCore
import OmniPreviewUI

@main
struct OmniPreviewApp: App {
    // Keeps the process alive after all windows close (see AppDelegate).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        // LSUIElement=true suppresses the Dock icon.
        // The tester window is opened on demand from the menu.
        Window("Preview Tester", id: "tester") {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }
        .commandsRemoved()

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
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
        }

        Divider()

        Button("About OmniPreview") {
            // Do NOT call NSApp.activate before the panel — for LSUIElement
            // apps, activating restores the last-open window (Settings),
            // which is the bug. The About panel works without activation.
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Rich Quick Look previews for archives, ML models, databases, certificates, and more.",
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                ),
            ])
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit OmniPreview") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Opens the Settings window. For LSUIElement agents the app must be
/// activated before the Settings scene responds to the open request.
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            OpenSettingsButton()
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}

@available(macOS 14.0, *)
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

struct ContentView: View {
    @State private var previewedDocument: PreviewDocument?
    @State private var previewError: String?
    @State private var previewedURL: URL?
    @State private var previewedIsImage = false
    @State private var showAnnotationEditor = false

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
            if previewedIsImage, let previewedURL {
                Button {
                    showAnnotationEditor = true
                } label: {
                    Label("Annotate", systemImage: "pencil.tip.crop.circle")
                }
                .help("Open the annotation editor (pen, lines, rectangles, text)")
                .id(previewedURL)
            }
            if previewedDocument != nil {
                Button("Clear") {
                    previewedDocument = nil
                    previewedURL = nil
                    previewedIsImage = false
                }
            }
        }
        .sheet(isPresented: $showAnnotationEditor) {
            if let previewedURL {
                ImageAnnotationView(imageURL: previewedURL)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    do {
                        previewedDocument = try await PreviewPipeline.shared.document(for: url)
                        previewedURL = url
                        if case .image = (try? FileTypeDetector.detect(url: url))?.kind {
                            previewedIsImage = true
                        } else {
                            previewedIsImage = false
                        }
                        previewError = nil
                    } catch {
                        previewedDocument = nil
                        previewedURL = nil
                        previewedIsImage = false
                        previewError = error.localizedDescription
                    }
                }
            }
            return true
        }
    }
}
