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
        case .zip, .tar, .gzip, .sevenZip, .rar, .xz, .bzip2, .cab, .arArchive, .xar:
            return "doc.zipper"
        case .iso, .dmg, .diskImage: return "externaldrive"
        case .rpmPackage: return "shippingbox"
        case .compoundFile: return "doc"
        case .sqlite, .sqlDump: return "cylinder.split.1x2"
        case .safetensors, .gguf, .onnx: return "brain"
        case .npy: return "square.grid.3x3"
        case .dataFile: return "chart.bar.doc.horizontal"
        case .terraformState: return "square.stack.3d.up"
        case .torrent: return "arrow.down.circle"
        case .pemCertificate, .derCertificate, .pkcs12: return "checkmark.seal"
        case .font: return "textformat"
        case .sourceCode: return "chevron.left.forwardslash.chevron.right"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .texture: return "photo.on.rectangle"
        case .audio: return "waveform"
        case .video: return "film"
        case .mobi, .fb2: return "book.closed"
        case .model3D: return "cube"
        case .cad: return "compass.drawing"
        case .geo: return "map"
        case .unknown: return "doc"
        }
    }
}
