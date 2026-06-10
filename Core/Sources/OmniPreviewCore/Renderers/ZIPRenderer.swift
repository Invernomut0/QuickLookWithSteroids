import Foundation

/// Lists ZIP contents from the central directory — no entry is decompressed
/// for the listing, which makes zip bombs harmless by construction.
/// Specialized ZIP-based formats (EPUB, Office, JAR, …) are handled by
/// dedicated renderers registered ahead of this one.
public struct ZIPRenderer: PreviewRenderer {
    public static let id = "zip"
    public static let displayName = "ZIP Archive"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .zip }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        let entries = archive.entries

        let totalUncompressed = entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        let totalCompressed = entries.reduce(UInt64(0)) { $0 + $1.compressedSize }
        let fileCount = entries.filter { !$0.isDirectory }.count
        let dirCount = entries.filter { $0.isDirectory }.count
        let ratio = totalUncompressed > 0
            ? String(format: "%.0f%%", 100.0 * (1.0 - Double(totalCompressed) / Double(totalUncompressed)))
            : "—"

        var rows = [
            KeyValueRow("Files", "\(fileCount)"),
        ]
        if dirCount > 0 { rows.append(KeyValueRow("Folders", "\(dirCount)")) }
        rows += [
            KeyValueRow("Uncompressed", Format.bytes(totalUncompressed)),
            KeyValueRow("Compressed", Format.bytes(totalCompressed)),
            KeyValueRow("Space saved", ratio),
            KeyValueRow("Archive size", Format.bytes(file.fileSize)),
        ]
        if archive.truncated {
            rows.append(KeyValueRow("Note", "Listing truncated to \(ZIPArchive.maxEntries) entries"))
        }

        let tree = archive.buildTree()

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "ZIP Archive",
            iconSystemName: "doc.zipper",
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .folderTree(nodes: tree),
            ]
        )
    }
}
