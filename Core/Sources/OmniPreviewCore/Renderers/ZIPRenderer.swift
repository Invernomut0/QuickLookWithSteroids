import Foundation

/// Lists ZIP contents by parsing only the central directory — no entry is
/// ever decompressed, which makes zip bombs harmless by construction.
public struct ZIPRenderer: PreviewRenderer {
    public static let id = "zip"
    public static let displayName = "ZIP Archive"

    static let maxCentralDirectorySize: UInt32 = 64 * 1024 * 1024
    static let maxEntries = 50_000

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .zip }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let listing = try Self.readListing(url: file.url, fileSize: file.fileSize)

        let totalUncompressed = listing.entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        let totalCompressed = listing.entries.reduce(UInt64(0)) { $0 + $1.compressedSize }
        let fileCount = listing.entries.filter { !$0.isDirectory }.count
        let ratio = totalUncompressed > 0
            ? String(format: "%.0f%%", 100.0 * (1.0 - Double(totalCompressed) / Double(totalUncompressed)))
            : "—"

        var rows = [
            KeyValueRow("Files", "\(fileCount)"),
            KeyValueRow("Uncompressed", Format.bytes(totalUncompressed)),
            KeyValueRow("Compressed", Format.bytes(totalCompressed)),
            KeyValueRow("Space saved", ratio),
            KeyValueRow("Archive size", Format.bytes(file.fileSize)),
        ]
        if listing.truncated {
            rows.append(KeyValueRow("Note", "Listing truncated to \(Self.maxEntries) entries"))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "ZIP Archive",
            iconSystemName: "doc.zipper",
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .fileTree(title: "Contents", entries: listing.entries),
            ]
        )
    }

    struct Listing {
        var entries: [ArchiveEntry]
        var truncated: Bool
    }

    static func readListing(url: URL, fileSize: UInt64) throws -> Listing {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // The end-of-central-directory record is in the last 22..(22+65535)
        // bytes; scan a 66 KB tail for its signature.
        let tailSize = min(fileSize, 66 * 1024)
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
        let tailBytes = [UInt8](tail)

        guard let eocdIndex = findEOCD(in: tailBytes) else {
            throw PreviewError.corruptFile("end-of-central-directory record not found")
        }

        var eocd = DataReader(Data(tailBytes[eocdIndex...]))
        try eocd.skip(4) // signature
        try eocd.skip(2 + 2 + 2) // disk numbers, entries on this disk
        let totalEntries = try eocd.readU16LE()
        let cdSize = try eocd.readU32LE()
        let cdOffset = try eocd.readU32LE()

        if totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF {
            throw PreviewError.unsupportedType // ZIP64: planned, not yet parsed
        }
        guard cdSize <= maxCentralDirectorySize else {
            throw PreviewError.tooLarge("central directory exceeds \(Format.bytes(UInt64(maxCentralDirectorySize)))")
        }
        guard UInt64(cdOffset) + UInt64(cdSize) <= fileSize else {
            throw PreviewError.corruptFile("central directory extends past end of file")
        }

        try handle.seek(toOffset: UInt64(cdOffset))
        let cdData = try handle.read(upToCount: Int(cdSize)) ?? Data()
        var reader = DataReader(cdData)

        var entries: [ArchiveEntry] = []
        var truncated = false
        while reader.remaining >= 46 {
            guard try reader.readU32LE() == 0x02014b50 else { break }
            try reader.skip(2 + 2 + 2 + 2) // versions, flags, method
            let dosTime = try reader.readU16LE()
            let dosDate = try reader.readU16LE()
            try reader.skip(4) // crc
            let compressed = try reader.readU32LE()
            let uncompressed = try reader.readU32LE()
            let nameLength = try reader.readU16LE()
            let extraLength = try reader.readU16LE()
            let commentLength = try reader.readU16LE()
            try reader.skip(2 + 2 + 4 + 4) // disk start, attrs, local header offset
            let name = try reader.readString(Int(nameLength))
            try reader.skip(Int(extraLength) + Int(commentLength))

            if entries.count >= maxEntries {
                truncated = true
                break
            }
            entries.append(ArchiveEntry(
                path: name,
                isDirectory: name.hasSuffix("/"),
                uncompressedSize: UInt64(uncompressed),
                compressedSize: UInt64(compressed),
                modified: dosDateTime(date: dosDate, time: dosTime)
            ))
        }
        return Listing(entries: entries, truncated: truncated)
    }

    private static func findEOCD(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
