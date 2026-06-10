import AppKit
import SwiftUI
import QuickLookUI
import OmniPreviewCore
import OmniPreviewUI

final class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Diagnostic: visible in Console.app filtering by "OmniPreview".
        // Confirms the extension was actually invoked by Quick Look.
        NSLog("[OmniPreview] preview requested for %@ (ext=%@)",
              url.path,
              url.pathExtension)
        let document: PreviewDocument
        do {
            document = try await PreviewPipeline.shared.document(for: url)
        } catch {
            NSLog("[OmniPreview] pipeline failed for %@: %@",
                  url.lastPathComponent,
                  String(describing: error))
            throw error
        }
        NSLog("[OmniPreview] rendered %@ -> %@ (%d sections)",
              url.lastPathComponent,
              document.title,
              document.sections.count)
        let host = NSHostingView(rootView: PreviewDocumentView(document: document))
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
