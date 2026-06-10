import Foundation

/// Central-directory-based ZIP access: listing plus bounded extraction of
/// individual entries (stored or deflate). Extraction is capped, so archive
/// bombs cannot expand past `maxBytes`.
struct ZIPArchive {
    struct Entry {
        let path: String
        let method: UInt16 // 0 = stored, 8 = deflate
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let modified: Date?
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    static let maxCentralDirectorySize: UInt32 = 64 * 1024 * 1024
    static let maxEntries = 50_000

    let url: URL
    let fileSize: UInt64
    let entries: [Entry]
    let truncated: Bool

    init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        try self.init(url: url, fileSize: (attributes[.size] as? UInt64) ?? 0)
    }

    init(url: URL, fileSize: UInt64) throws {
        self.url = url
        self.fileSize = fileSize

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // The end-of-central-directory record is within the last 22+65535 bytes.
        let tailSize = min(fileSize, 66 * 1024)
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = [UInt8](try handle.read(upToCount: Int(tailSize)) ?? Data())

        guard let eocdIndex = Self.findEOCD(in: tail) else {
            throw PreviewError.corruptFile("end-of-central-directory record not found")
        }
        var eocd = DataReader(Data(tail[eocdIndex...]))
        try eocd.skip(4 + 2 + 2 + 2)
        let totalEntries = try eocd.readU16LE()
        let cdSize = try eocd.readU32LE()
        let cdOffset = try eocd.readU32LE()

        if totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF {
            throw PreviewError.unsupportedType // ZIP64: planned, not yet parsed
        }
        guard cdSize <= Self.maxCentralDirectorySize else {
            throw PreviewError.tooLarge("central directory exceeds \(Format.bytes(UInt64(Self.maxCentralDirectorySize)))")
        }
        guard UInt64(cdOffset) + UInt64(cdSize) <= fileSize else {
            throw PreviewError.corruptFile("central directory extends past end of file")
        }

        try handle.seek(toOffset: UInt64(cdOffset))
        var reader = DataReader(try handle.read(upToCount: Int(cdSize)) ?? Data())

        var parsed: [Entry] = []
        var wasTruncated = false
        while reader.remaining >= 46 {
            guard try reader.readU32LE() == 0x02014b50 else { break }
            try reader.skip(2 + 2 + 2)
            let method = try reader.readU16LE()
            let dosTime = try reader.readU16LE()
            let dosDate = try reader.readU16LE()
            try reader.skip(4) // crc
            let compressed = try reader.readU32LE()
            let uncompressed = try reader.readU32LE()
            let nameLength = try reader.readU16LE()
            let extraLength = try reader.readU16LE()
            let commentLength = try reader.readU16LE()
            try reader.skip(2 + 2 + 4) // disk start, internal attrs, external attrs
            let localOffset = try reader.readU32LE()
            let name = try reader.readString(Int(nameLength))
            try reader.skip(Int(extraLength) + Int(commentLength))

            if parsed.count >= Self.maxEntries {
                wasTruncated = true
                break
            }
            parsed.append(Entry(
                path: name,
                method: method,
                compressedSize: UInt64(compressed),
                uncompressedSize: UInt64(uncompressed),
                localHeaderOffset: UInt64(localOffset),
                modified: Self.dosDateTime(date: dosDate, time: dosTime)
            ))
        }
        self.entries = parsed
        self.truncated = wasTruncated
    }

    func entry(at path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    func firstEntry(withSuffix suffix: String) -> Entry? {
        entries.first { $0.path.lowercased().hasSuffix(suffix) }
    }

    /// Full extraction; throws if the declared size exceeds `maxBytes`.
    func extract(_ entry: Entry, maxBytes: Int) throws -> Data {
        guard entry.uncompressedSize <= UInt64(maxBytes) else {
            throw PreviewError.tooLarge("entry \(entry.path) exceeds \(Format.bytes(UInt64(maxBytes)))")
        }
        return try extractPrefix(entry, maxBytes: maxBytes)
    }

    /// Extracts up to `maxBytes` of decompressed data (prefix for larger entries).
    func extractPrefix(_ entry: Entry, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Local header name/extra lengths can differ from the central directory.
        try handle.seek(toOffset: entry.localHeaderOffset)
        var header = DataReader(try handle.read(upToCount: 30) ?? Data())
        guard try header.readU32LE() == 0x04034b50 else {
            throw PreviewError.corruptFile("bad local header for \(entry.path)")
        }
        try header.skip(2 + 2 + 2 + 2 + 2 + 4 + 4 + 4)
        let nameLength = try header.readU16LE()
        let extraLength = try header.readU16LE()

        let dataOffset = entry.localHeaderOffset + 30 + UInt64(nameLength) + UInt64(extraLength)
        guard dataOffset + entry.compressedSize <= fileSize else {
            throw PreviewError.corruptFile("entry data extends past end of file")
        }
        try handle.seek(toOffset: dataOffset)
        // For stored entries a prefix read suffices; deflate needs the full
        // compressed stream (bounded by the central-directory cap anyway).
        let compressedCap = entry.method == 0 ? min(entry.compressedSize, UInt64(maxBytes)) : entry.compressedSize
        guard compressedCap <= 512 * 1024 * 1024 else {
            throw PreviewError.tooLarge("compressed entry too large")
        }
        let compressed = try handle.read(upToCount: Int(compressedCap)) ?? Data()

        switch entry.method {
        case 0:
            return compressed.prefix(maxBytes)
        case 8:
            guard let result = Decompressor.inflateRaw(compressed, maxOutput: maxBytes) else {
                throw PreviewError.corruptFile("deflate stream for \(entry.path) is invalid")
            }
            return result.data
        default:
            throw PreviewError.unsupportedType
        }
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

    static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
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

    var archiveEntries: [ArchiveEntry] {
        entries.map {
            ArchiveEntry(
                path: $0.path,
                isDirectory: $0.isDirectory,
                uncompressedSize: $0.uncompressedSize,
                compressedSize: $0.compressedSize,
                modified: $0.modified
            )
        }
    }
}
