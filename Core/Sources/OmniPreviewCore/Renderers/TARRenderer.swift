import Foundation

/// Lists TAR contents by walking the 512-byte headers and seeking past each
/// entry's data — file contents are never read into memory.
public struct TARRenderer: PreviewRenderer {
    public static let id = "tar"
    public static let displayName = "TAR Archive"

    static let blockSize = 512
    static let maxEntries = 50_000

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .tar }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let (entries, truncated) = try Self.readListing(url: file.url, fileSize: file.fileSize)

        let totalSize = entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        let fileCount = entries.filter { !$0.isDirectory }.count

        var rows = [
            KeyValueRow("Files", "\(fileCount)"),
            KeyValueRow("Total size", Format.bytes(totalSize)),
            KeyValueRow("Archive size", Format.bytes(file.fileSize)),
        ]
        if truncated {
            rows.append(KeyValueRow("Note", "Listing truncated to \(Self.maxEntries) entries"))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "TAR Archive",
            iconSystemName: "doc.zipper",
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .fileTree(title: "Contents", entries: entries),
            ]
        )
    }

    static func readListing(url: URL, fileSize: UInt64) throws -> (entries: [ArchiveEntry], truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var entries: [ArchiveEntry] = []
        var offset: UInt64 = 0
        var pendingLongName: String?

        while offset + UInt64(blockSize) <= fileSize {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: blockSize), header.count == blockSize else { break }
            let block = [UInt8](header)

            // Two consecutive zero blocks terminate the archive; one is enough to stop listing.
            if block.allSatisfy({ $0 == 0 }) { break }

            let size = octal(block, 124, 12)
            let typeFlag = block[156]
            let dataBlocks = (size + UInt64(blockSize) - 1) / UInt64(blockSize)

            // GNU long-name extension: entry data holds the real name of the next entry.
            if typeFlag == UInt8(ascii: "L") {
                let nameData = try handle.read(upToCount: Int(min(size, 4096))) ?? Data()
                pendingLongName = String(decoding: nameData, as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                offset += UInt64(blockSize) + dataBlocks * UInt64(blockSize)
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
                return (entries, true)
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
            offset += UInt64(blockSize) + dataBlocks * UInt64(blockSize)
        }
        return (entries, false)
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
