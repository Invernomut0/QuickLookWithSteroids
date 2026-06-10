import AppKit
import QuickLookThumbnailing
import OmniPreviewCore

/// Draws a fast, metadata-light thumbnail card: file-type icon plus the
/// uppercased extension. Heavier, renderer-driven thumbnails are planned.
final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let size = request.maximumSize

        guard let file = try? FileTypeDetector.detect(url: url),
              RendererRegistry.renderer(for: file) != nil else {
            handler(nil, nil)
            return
        }
        let icon = Self.iconName(for: file.kind)
        let label = url.pathExtension.uppercased()

        let reply = QLThumbnailReply(contextSize: size) {
            let bounds = CGRect(origin: .zero, size: size)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: size.width * 0.08, yRadius: size.width * 0.08).fill()

            let configuration = NSImage.SymbolConfiguration(pointSize: size.height * 0.38, weight: .medium)
            if let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                let symbolRect = CGRect(
                    x: (size.width - symbol.size.width) / 2,
                    y: size.height * 0.58 - symbol.size.height / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: symbolRect)
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size.height * 0.14, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height * 0.16))
            return true
        }
        handler(reply, nil)
    }

    private static func iconName(for kind: FileKind) -> String {
        switch kind {
        case .zip, .tar, .gzip, .sevenZip, .rar, .xz: return "doc.zipper"
        case .sqlite: return "cylinder.split.1x2"
        case .safetensors: return "brain"
        case .gguf: return "cpu"
        case .pemCertificate, .derCertificate: return "checkmark.seal"
        case .font: return "textformat"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .npy: return "square.grid.3x3"
        case .unknown: return "doc"
        }
    }
}
