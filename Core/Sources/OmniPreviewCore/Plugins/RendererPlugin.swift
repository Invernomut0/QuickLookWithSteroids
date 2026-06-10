import Foundation

/// A renderer plugin turns one family of files into a `PreviewDocument`.
/// Renderers must be read-only, must never execute file contents, and must
/// enforce their own size/entry caps to stay within memory budgets.
public protocol PreviewRenderer: Sendable {
    static var id: String { get }
    static var displayName: String { get }
    func canRender(_ file: DetectedFile) -> Bool
    /// Async so renderers can use modern loading APIs (AVFoundation);
    /// most renderers implement this synchronously.
    func render(_ file: DetectedFile) async throws -> PreviewDocument
}

public enum RendererRegistry {
    public static let all: [any PreviewRenderer] = [
        ZIPRenderer(),
        TARRenderer(),
        GzipRenderer(),
        SQLiteRenderer(),
        SafetensorsRenderer(),
        GGUFRenderer(),
        NPYRenderer(),
        PDFRenderer(),
        ImageRenderer(),
        MediaRenderer(),
        CertificateRenderer(),
        FontRenderer(),
        SourceCodeRenderer(),
    ]

    public static func renderer(for file: DetectedFile) -> (any PreviewRenderer)? {
        all.first { $0.canRender(file) }
    }
}
