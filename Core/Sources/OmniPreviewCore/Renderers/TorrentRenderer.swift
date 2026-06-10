import Foundation

/// BitTorrent metadata via a bounded bencode parser: name, trackers, piece
/// size, file list, total size.
public struct TorrentRenderer: PreviewRenderer {
    public static let id = "torrent"
    public static let displayName = "Torrent"

    static let maxRead = 16 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .torrent }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxRead) ?? Data()

        var reader = DataReader(data)
        guard let root = try Bencode.parse(&reader, depth: 0) as? [String: Any] else {
            throw PreviewError.corruptFile("not a bencoded dictionary")
        }
        guard let info = root["info"] as? [String: Any] else {
            throw PreviewError.corruptFile("missing info dictionary")
        }

        var rows: [KeyValueRow] = []
        if let name = info["name"] as? String { rows.append(KeyValueRow("Name", name)) }
        if let announce = root["announce"] as? String { rows.append(KeyValueRow("Tracker", announce)) }
        if let createdBy = root["created by"] as? String { rows.append(KeyValueRow("Created by", createdBy)) }
        if let date = root["creation date"] as? Int64 {
            rows.append(KeyValueRow("Created", Format.date(Date(timeIntervalSince1970: TimeInterval(date)))))
        }
        if let pieceLength = info["piece length"] as? Int64 {
            rows.append(KeyValueRow("Piece size", Format.bytes(UInt64(max(pieceLength, 0)))))
        }
        if root["announce-list"] is [Any] {
            let trackers = (root["announce-list"] as? [[Any]])?.flatMap { $0 }.compactMap { $0 as? String } ?? []
            if trackers.count > 1 {
                rows.append(KeyValueRow("Trackers", "\(trackers.count)"))
            }
        }
        rows.append(KeyValueRow("Private", (info["private"] as? Int64) == 1 ? "Yes" : "No"))

        var entries: [ArchiveEntry] = []
        var totalSize: UInt64 = 0
        if let files = info["files"] as? [[String: Any]] {
            for fileEntry in files.prefix(2000) {
                let parts = (fileEntry["path"] as? [Any])?.compactMap { $0 as? String } ?? []
                let length = UInt64(max(fileEntry["length"] as? Int64 ?? 0, 0))
                totalSize += length
                entries.append(ArchiveEntry(
                    path: parts.joined(separator: "/"), isDirectory: false,
                    uncompressedSize: length, compressedSize: length, modified: nil
                ))
            }
        } else if let length = info["length"] as? Int64 {
            totalSize = UInt64(max(length, 0))
        }
        rows.insert(KeyValueRow("Total size", Format.bytes(totalSize)), at: 1)

        var sections: [PreviewSection] = [.keyValues(title: "Torrent", rows: rows)]
        if !entries.isEmpty {
            sections.append(.fileTree(title: "Files (\(entries.count))", entries: entries))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "BitTorrent Metadata",
            iconSystemName: "arrow.down.circle",
            sections: sections
        )
    }
}

/// Minimal bencode decoder. Strings decode as UTF-8 when possible (binary
/// values like `pieces` fall back to a placeholder); depth and count are
/// bounded against hostile input.
enum Bencode {
    static let maxDepth = 16
    static let maxItems = 100_000

    static func parse(_ reader: inout DataReader, depth: Int) throws -> Any {
        guard depth < maxDepth else { throw PreviewError.corruptFile("bencode nesting too deep") }
        let marker = try reader.readU8()
        switch marker {
        case UInt8(ascii: "i"):
            return try integer(&reader, terminator: UInt8(ascii: "e"))
        case UInt8(ascii: "l"):
            var list: [Any] = []
            while try peek(&reader) != UInt8(ascii: "e"), list.count < maxItems {
                list.append(try parse(&reader, depth: depth + 1))
            }
            try reader.skip(1)
            return list
        case UInt8(ascii: "d"):
            var dictionary: [String: Any] = [:]
            while try peek(&reader) != UInt8(ascii: "e"), dictionary.count < maxItems {
                guard let key = try parse(&reader, depth: depth + 1) as? String else {
                    throw PreviewError.corruptFile("bencode dictionary key is not a string")
                }
                dictionary[key] = try parse(&reader, depth: depth + 1)
            }
            try reader.skip(1)
            return dictionary
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            var length = Int(marker - UInt8(ascii: "0"))
            while try peek(&reader) != UInt8(ascii: ":") {
                let digit = try reader.readU8()
                guard digit >= UInt8(ascii: "0"), digit <= UInt8(ascii: "9"), length < 100_000_000 else {
                    throw PreviewError.corruptFile("invalid bencode string length")
                }
                length = length * 10 + Int(digit - UInt8(ascii: "0"))
            }
            try reader.skip(1)
            let bytes = try reader.read(length)
            if let text = String(bytes: bytes, encoding: .utf8) {
                return text
            }
            return "<\(length) bytes binary>"
        default:
            throw PreviewError.corruptFile("unexpected bencode marker \(marker)")
        }
    }

    private static func integer(_ reader: inout DataReader, terminator: UInt8) throws -> Int64 {
        var text = ""
        for _ in 0..<24 {
            let byte = try reader.readU8()
            if byte == terminator {
                guard let value = Int64(text) else {
                    throw PreviewError.corruptFile("invalid bencode integer")
                }
                return value
            }
            text.append(Character(UnicodeScalar(byte)))
        }
        throw PreviewError.corruptFile("bencode integer too long")
    }

    private static func peek(_ reader: inout DataReader) throws -> UInt8 {
        guard reader.remaining > 0 else { throw PreviewError.corruptFile("unexpected end of bencode data") }
        var copy = reader
        return try copy.readU8()
    }
}
