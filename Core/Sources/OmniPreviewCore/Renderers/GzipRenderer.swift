import Foundation

/// Gzip preview: header metadata plus — when the member is a tarball — the
/// contained file tree via bounded decompression.
public struct GzipRenderer: PreviewRenderer {
    public static let id = "gzip"
    public static let displayName = "Gzip Archive"

    /// Decompression output cap; tarballs larger than this list partially.
    static let maxDecompressed = 128 * 1024 * 1024
    static let maxCompressedRead = 256 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .gzip }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let headerData = try handle.read(upToCount: 4096) ?? Data()
        var reader = DataReader(headerData)

        guard try reader.readU8() == 0x1F, try reader.readU8() == 0x8B else {
            throw PreviewError.corruptFile("bad gzip magic")
        }
        let method = try reader.readU8()
        let flags = try reader.readU8()
        let mtime = try reader.readU32LE()
        try reader.skip(1)
        let os = try reader.readU8()

        if flags & 0x04 != 0 {
            let extraLength = try reader.readU16LE()
            try reader.skip(Int(extraLength))
        }
        var originalName: String?
        if flags & 0x08 != 0 {
            var nameBytes: [UInt8] = []
            while let byte = try? reader.readU8(), byte != 0 { nameBytes.append(byte) }
            originalName = String(bytes: nameBytes, encoding: .isoLatin1)
        }

        var rows = [KeyValueRow("Compression", method == 8 ? "deflate" : "method \(method)")]
        if let originalName {
            rows.append(KeyValueRow("Original file", originalName))
        }
        if mtime > 0 {
            rows.append(KeyValueRow("Modified", Format.date(Date(timeIntervalSince1970: TimeInterval(mtime)))))
        }
        rows.append(KeyValueRow("Created on", Self.osName(os)))
        rows.append(KeyValueRow("Compressed size", Format.bytes(file.fileSize)))

        // Tarball? List contents through bounded decompression.
        let baseName = file.url.lastPathComponent.lowercased()
        let isTarball = baseName.hasSuffix(".tar.gz") || baseName.hasSuffix(".tgz")
            || originalName?.lowercased().hasSuffix(".tar") == true
        if isTarball, file.fileSize <= UInt64(Self.maxCompressedRead) {
            try handle.seek(toOffset: 0)
            let compressed = try handle.read(upToCount: Self.maxCompressedRead) ?? Data()
            if let inflated = Decompressor.inflateGzip(compressed, maxOutput: Self.maxDecompressed) {
                var listing = TARRenderer.listing(from: inflated.data)
                listing.truncated = listing.truncated || inflated.truncated
                return TARRenderer.document(
                    title: file.url.lastPathComponent,
                    subtitle: "Compressed TAR Archive (gzip)",
                    archiveSize: file.fileSize,
                    listing: listing,
                    extraRows: rows
                )
            }
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Gzip Archive",
            iconSystemName: "doc.zipper",
            sections: [.keyValues(title: "Summary", rows: rows)]
        )
    }

    private static func osName(_ code: UInt8) -> String {
        switch code {
        case 0: return "FAT (DOS/Windows)"
        case 3: return "Unix"
        case 7: return "Macintosh"
        case 11: return "NTFS (Windows)"
        case 255: return "Unknown"
        default: return "OS code \(code)"
        }
    }
}

/// XZ preview; tarballs (.tar.xz) get a contents listing via bounded
/// decompression (Compression framework LZMA implementation).
public struct XZRenderer: PreviewRenderer {
    public static let id = "xz"
    public static let displayName = "XZ Archive"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .xz }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let rows = [KeyValueRow("Compressed size", Format.bytes(file.fileSize))]

        let baseName = file.url.lastPathComponent.lowercased()
        if baseName.hasSuffix(".tar.xz") || baseName.hasSuffix(".txz"),
           file.fileSize <= UInt64(GzipRenderer.maxCompressedRead) {
            let compressed = try Data(contentsOf: file.url, options: .alwaysMapped)
            if let inflated = Decompressor.inflateXZ(compressed, maxOutput: GzipRenderer.maxDecompressed) {
                var listing = TARRenderer.listing(from: inflated.data)
                listing.truncated = listing.truncated || inflated.truncated
                return TARRenderer.document(
                    title: file.url.lastPathComponent,
                    subtitle: "Compressed TAR Archive (xz)",
                    archiveSize: file.fileSize,
                    listing: listing,
                    extraRows: rows
                )
            }
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "XZ Archive",
            iconSystemName: "doc.zipper",
            sections: [.keyValues(title: "Summary", rows: rows)]
        )
    }
}
