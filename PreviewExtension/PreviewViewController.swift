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
        let document = try await PreviewPipeline.shared.document(for: url)
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
