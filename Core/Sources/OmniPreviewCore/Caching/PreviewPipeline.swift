import Foundation

/// Detection → renderer lookup → render, with an in-memory cache keyed by
/// path + size + modification time so unchanged files render once.
public final class PreviewPipeline: @unchecked Sendable {
    public static let shared = PreviewPipeline()

    private final class Box {
        let document: PreviewDocument
        init(_ document: PreviewDocument) { self.document = document }
    }

    private let cache = NSCache<NSString, Box>()

    public init(cacheCountLimit: Int = 64) {
        cache.countLimit = cacheCountLimit
    }

    public func clearCache() {
        cache.removeAllObjects()
    }

    public func document(for url: URL) async throws -> PreviewDocument {
        let key = try Self.cacheKey(for: url)
        if let cached = cache.object(forKey: key as NSString) {
            return cached.document
        }
        let document = try await Task.detached(priority: .userInitiated) {
            let file = try FileTypeDetector.detect(url: url)
            guard let renderer = RendererRegistry.renderer(for: file) else {
                return Self.fallbackDocument(for: file, reason: PreviewError.unsupportedType)
            }
            do {
                return try await renderer.render(file)
            } catch {
                return Self.fallbackDocument(for: file, reason: error)
            }
        }.value
        cache.setObject(Box(document), forKey: key as NSString)
        return document
    }

    private static func fallbackDocument(for file: DetectedFile, reason: Error) -> PreviewDocument {
        var rows: [KeyValueRow] = [
            KeyValueRow("Detected type", String(describing: file.kind)),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if !file.pathExtension.isEmpty {
            rows.append(KeyValueRow("Extension", file.pathExtension))
        }
        if let previewError = reason as? PreviewError, let message = previewError.errorDescription {
            rows.append(KeyValueRow("Note", message))
        } else {
            rows.append(KeyValueRow("Note", "Rendering fallback used."))
        }

        let sample: Data
        if let handle = try? FileHandle(forReadingFrom: file.url) {
            sample = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
            try? handle.close()
        } else {
            sample = Data()
        }
        let looksText = FileTypeDetector.looksLikeTextSample(sample)

        var sections: [PreviewSection] = [.keyValues(title: "Preview", rows: rows)]
        if looksText {
            let content = String(decoding: sample, as: UTF8.self)
            sections.append(.text(content: content, language: nil))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Fallback Preview",
            iconSystemName: looksText ? "doc.text" : "doc",
            sections: sections
        )
    }

    static func cacheKey(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(modified)"
    }
}
