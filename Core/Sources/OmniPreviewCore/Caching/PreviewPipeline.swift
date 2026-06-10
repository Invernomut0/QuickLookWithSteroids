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

    public func document(for url: URL) async throws -> PreviewDocument {
        let key = try Self.cacheKey(for: url)
        if let cached = cache.object(forKey: key as NSString) {
            return cached.document
        }
        let document = try await Task.detached(priority: .userInitiated) {
            let file = try FileTypeDetector.detect(url: url)
            guard let renderer = RendererRegistry.renderer(for: file) else {
                throw PreviewError.unsupportedType
            }
            return try await renderer.render(file)
        }.value
        cache.setObject(Box(document), forKey: key as NSString)
        return document
    }

    static func cacheKey(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(modified)"
    }
}
