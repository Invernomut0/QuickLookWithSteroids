import SwiftUI
import OmniPreviewCore
import OmniPreviewUI

@main
struct OmniPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }
    }
}

struct ContentView: View {
    @State private var previewedDocument: PreviewDocument?
    @State private var previewError: String?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Renderer Plugins") {
                    ForEach(RendererRegistry.all, id: \.self.idString) { renderer in
                        Label(type(of: renderer).displayName, systemImage: "puzzlepiece.extension")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let document = previewedDocument {
                PreviewDocumentView(document: document)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("OmniPreview")
                        .font(.title2.weight(.semibold))
                    Text("Quick Look extensions are active once this app has been launched.\nPress Space on a supported file in Finder, or drop a file here to test rendering.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let previewError {
                        Text(previewError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
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

private extension PreviewRenderer {
    var idString: String { type(of: self).id }
}
