import Foundation

/// Lists TAR contents by walking the 512-byte headers — file data is never
/// materialized (the file is memory-mapped, entry data is skipped over).
public struct TARRenderer: PreviewRenderer {
    public static let id = "tar"
    public static let displayName = "TAR Archive"

    static let blockSize = 512
    static let maxEntries = 50_000

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .tar }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let data = try Data(contentsOf: file.url, options: .alwaysMapped)
        let listing = Self.listing(from: data)
        return Self.document(
            title: file.url.lastPathComponent,
            subtitle: "TAR Archive",
            archiveSize: file.fileSize,
            listing: listing
        )
    }

    struct Listing {
        var entries: [ArchiveEntry]
        var truncated: Bool
    }

    static func document(title: String, subtitle: String, archiveSize: UInt64, listing: Listing,
                         extraRows: [KeyValueRow] = []) -> PreviewDocument {
        let totalSize = listing.entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        let fileCount = listing.entries.filter { !$0.isDirectory }.count

        var rows = [
            KeyValueRow("Files", "\(fileCount)"),
            KeyValueRow("Total size", Format.bytes(totalSize)),
            KeyValueRow("Archive size", Format.bytes(archiveSize)),
        ]
        rows.append(contentsOf: extraRows)
        if listing.truncated {
            rows.append(KeyValueRow("Note", "Listing truncated"))
        }

        return PreviewDocument(
            title: title,
            subtitle: subtitle,
            iconSystemName: "doc.zipper",
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .fileTree(title: "Contents", entries: listing.entries),
            ]
        )
    }

    /// Walks ustar headers in a buffer (a mapped file or a decompressed stream).
    static func listing(from data: Data) -> Listing {
        let bytes = [UInt8](data)
        var entries: [ArchiveEntry] = []
        var offset = 0
        var pendingLongName: String?

        while offset + blockSize <= bytes.count {
            let block = Array(bytes[offset..<offset + blockSize])
            if block.allSatisfy({ $0 == 0 }) { break }

            let size = octal(block, 124, 12)
            let typeFlag = block[156]
            let dataBlocks = Int((size + UInt64(blockSize) - 1) / UInt64(blockSize))

            // GNU long-name extension: entry data holds the real name of the next entry.
            if typeFlag == UInt8(ascii: "L") {
                let nameEnd = min(offset + blockSize + Int(min(size, 4096)), bytes.count)
                pendingLongName = String(decoding: bytes[(offset + blockSize)..<nameEnd], as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                offset += blockSize + dataBlocks * blockSize
                continue
            }

            var name = pendingLongName ?? cString(block, 0, 100)
            pendingLongName = nil
            let prefix = cString(block, 345, 155)
            if !prefix.isEmpty, !name.hasPrefix(prefix) {
                name = prefix + "/" + name
            }
            let mtime = octal(block, 136, 12)

            if entries.count >= maxEntries {
                return Listing(entries: entries, truncated: true)
            }
            if !name.isEmpty {
                entries.append(ArchiveEntry(
                    path: name,
                    isDirectory: typeFlag == UInt8(ascii: "5") || name.hasSuffix("/"),
                    uncompressedSize: size,
                    compressedSize: size,
                    modified: mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
                ))
            }
            offset += blockSize + dataBlocks * blockSize
        }
        return Listing(entries: entries, truncated: false)
    }

    private static func cString(_ block: [UInt8], _ start: Int, _ length: Int) -> String {
        let slice = block[start..<start + length].prefix { $0 != 0 }
        return String(decoding: slice, as: UTF8.self)
    }

    private static func octal(_ block: [UInt8], _ start: Int, _ length: Int) -> UInt64 {
        let text = cString(block, start, length).trimmingCharacters(in: .whitespaces)
        return UInt64(text, radix: 8) ?? 0
    }
}
