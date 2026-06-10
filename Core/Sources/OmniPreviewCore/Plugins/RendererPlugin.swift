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
    /// Order matters: FolderRenderer first (detects .folder), then specialized
    /// ZIP-based renderers before the generic ZIP renderer.
    public static let all: [any PreviewRenderer] = [
        FolderRenderer(),
        OfficeRenderer(),
        EbookRenderer(),
        AppPackageRenderer(),
        GeoRenderer(),
        ThreeDRenderer(),
        ZIPRenderer(),
        TARRenderer(),
        GzipRenderer(),
        XZRenderer(),
        ArchiveMetadataRenderer(),
        SQLiteRenderer(),
        SafetensorsRenderer(),
        GGUFRenderer(),
        ONNXRenderer(),
        NPYRenderer(),
        PDFRenderer(),
        ImageRenderer(),
        TextureRenderer(),
        MediaRenderer(),
        DataFileRenderer(),
        DiskImageRenderer(),
        CADRenderer(),
        TorrentRenderer(),
        DumpRenderer(),
        CertificateRenderer(),
        FontRenderer(),
        YAMLRenderer(),  // before source-code
        INIRenderer(),   // before source-code
        SourceCodeRenderer(),
    ]

    public static func renderer(for file: DetectedFile) -> (any PreviewRenderer)? {
        guard let match = all.first(where: {
            RendererSettings.isEnabled(id: type(of: $0).id) && $0.canRender(file)
        }) else { return nil }

        let rid = type(of: match).id
        if ProTier.isPro(rendererID: rid) && !LicenseManager.shared.isProUnlocked {
            let info = ProTier.proFeatureDescriptions.first { $0.id == rid }
            return LockedRenderer(
                formatName: info?.name ?? type(of: match).displayName,
                iconSystemName: info?.icon ?? "lock.fill"
            )
        }
        return match
    }
}
