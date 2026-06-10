import Foundation

/// Gzip header metadata: original filename, modification date, producing OS.
/// Contents listing (tar.gz trees) requires bounded decompression — planned.
public struct GzipRenderer: PreviewRenderer {
    public static let id = "gzip"
    public static let displayName = "Gzip Archive"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .gzip }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        var reader = DataReader(try handle.read(upToCount: 4096) ?? Data())

        guard try reader.readU8() == 0x1F, try reader.readU8() == 0x8B else {
            throw PreviewError.corruptFile("bad gzip magic")
        }
        let method = try reader.readU8()
        let flags = try reader.readU8()
        let mtime = try reader.readU32LE()
        try reader.skip(1) // extra flags
        let os = try reader.readU8()

        if flags & 0x04 != 0 { // FEXTRA
            let extraLength = try reader.readU16LE()
            try reader.skip(Int(extraLength))
        }
        var originalName: String?
        if flags & 0x08 != 0 { // FNAME: null-terminated latin-1
            var bytes: [UInt8] = []
            while let byte = try? reader.readU8(), byte != 0 { bytes.append(byte) }
            originalName = String(bytes: bytes, encoding: .isoLatin1)
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

        let baseName = file.url.lastPathComponent.lowercased()
        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: rows)]
        if baseName.hasSuffix(".tar.gz") || baseName.hasSuffix(".tgz") || originalName?.hasSuffix(".tar") == true {
            sections.append(.note("Compressed tarball — contents listing requires decompression (planned)."))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Gzip Archive",
            iconSystemName: "doc.zipper",
            sections: sections
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
