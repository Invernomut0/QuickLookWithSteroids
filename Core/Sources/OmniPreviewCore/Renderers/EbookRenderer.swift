import Foundation

/// eBook previews: EPUB (OPF metadata + cover), comic archives (CBZ cover +
/// page count), MOBI/AZW3 (PalmDB title), FB2 (XML metadata).
public struct EbookRenderer: PreviewRenderer {
    public static let id = "ebook"
    public static let displayName = "eBooks"

    static let zipExtensions: Set<String> = ["epub", "cbz"]
    static let maxXML = 4 * 1024 * 1024
    static let maxCover = 16 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        switch file.kind {
        case .zip: return Self.zipExtensions.contains(file.pathExtension)
        case .mobi, .fb2: return true
        case .rar: return file.pathExtension == "cbr"
        default: return false
        }
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        switch (file.kind, file.pathExtension) {
        case (.zip, "epub"): return try renderEPUB(file)
        case (.zip, "cbz"): return try renderComic(file)
        case (.mobi, _): return try renderMOBI(file)
        case (.fb2, _): return try renderFB2(file)
        case (.rar, "cbr"):
            return ArchiveMetadataRenderer.simple(file, "Comic Book Archive (RAR)", "book.closed", [
                KeyValueRow("Archive size", Format.bytes(file.fileSize)),
                KeyValueRow("Note", "Page listing requires the RAR codec (planned)"),
            ])
        default: throw PreviewError.unsupportedType
        }
    }

    private func renderEPUB(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)

        // container.xml points at the OPF package document.
        guard let container = archive.entry(at: "META-INF/container.xml"),
              let containerXML = try? archive.extract(container, maxBytes: Self.maxXML),
              let containerDoc = try? XMLDocument(data: containerXML),
              let opfPath = try? containerDoc
                  .nodes(forXPath: "//*[local-name()='rootfile']/@full-path").first?.stringValue,
              let opfEntry = archive.entry(at: opfPath),
              let opfData = try? archive.extract(opfEntry, maxBytes: Self.maxXML),
              let opf = try? XMLDocument(data: opfData) else {
            throw PreviewError.corruptFile("missing or invalid EPUB package document")
        }

        func metadata(_ element: String) -> String? {
            (try? opf.nodes(forXPath: "//*[local-name()='\(element)']").first?.stringValue)?
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        var rows: [KeyValueRow] = []
        if let title = metadata("title") { rows.append(KeyValueRow("Title", title)) }
        if let creator = metadata("creator") { rows.append(KeyValueRow("Author", creator)) }
        if let publisher = metadata("publisher") { rows.append(KeyValueRow("Publisher", publisher)) }
        if let language = metadata("language") { rows.append(KeyValueRow("Language", language)) }
        if let date = metadata("date") { rows.append(KeyValueRow("Date", date)) }
        let chapterCount = (try? opf.nodes(forXPath: "//*[local-name()='itemref']").count) ?? 0
        if chapterCount > 0 { rows.append(KeyValueRow("Spine items", "\(chapterCount)")) }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        var sections: [PreviewSection] = []
        if let coverData = extractEPUBCover(archive: archive, opf: opf, opfPath: opfPath) {
            sections.append(.imageData(coverData))
        }
        sections.append(.keyValues(title: "Book", rows: rows))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "EPUB eBook",
            iconSystemName: "book.closed",
            sections: sections
        )
    }

    private func extractEPUBCover(archive: ZIPArchive, opf: XMLDocument, opfPath: String) -> Data? {
        // Try <meta name="cover" content="id"> then any manifest item with
        // properties="cover-image"; resolve href relative to the OPF directory.
        var coverHref: String?
        if let coverID = try? opf.nodes(forXPath: "//*[local-name()='meta'][@name='cover']/@content")
            .first?.stringValue {
            coverHref = try? opf.nodes(forXPath: "//*[local-name()='item'][@id='\(coverID)']/@href")
                .first?.stringValue
        }
        if coverHref == nil {
            coverHref = try? opf.nodes(forXPath: "//*[local-name()='item'][contains(@properties,'cover-image')]/@href")
                .first?.stringValue
        }
        guard let href = coverHref else { return nil }
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent
        let coverPath = opfDirectory.isEmpty ? href : opfDirectory + "/" + href
        guard let entry = archive.entry(at: coverPath) ?? archive.firstEntry(withSuffix: (href as NSString).lastPathComponent.lowercased()) else {
            return nil
        }
        return try? archive.extract(entry, maxBytes: Self.maxCover)
    }

    private func renderComic(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        let pages = archive.entries
            .filter { !$0.isDirectory && imageExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var sections: [PreviewSection] = []
        if let first = pages.first, let cover = try? archive.extract(first, maxBytes: Self.maxCover) {
            sections.append(.imageData(cover))
        }
        sections.append(.keyValues(title: "Comic", rows: [
            KeyValueRow("Pages", "\(pages.count)"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Comic Book Archive",
            iconSystemName: "book.closed",
            sections: sections
        )
    }

    /// MOBI/AZW3 are PalmDB containers: 32-byte name, then a MOBI header
    /// with a full-title pointer inside record 0.
    private func renderMOBI(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
        guard head.count > 78 else { throw PreviewError.corruptFile("truncated PalmDB header") }

        let dbName = String(decoding: head[0..<32].prefix { $0 != 0 }, as: UTF8.self)
        var rows = [
            KeyValueRow("Database name", dbName),
            KeyValueRow("Format", file.pathExtension == "azw3" ? "Kindle AZW3" : "MOBI"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        var reader = DataReader(head)
        try reader.skip(76)
        let recordCount = try reader.readU16LE().byteSwapped // PalmDB is big-endian
        rows.append(KeyValueRow("Records", "\(recordCount)"))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Kindle eBook",
            iconSystemName: "book.closed",
            sections: [.keyValues(title: "Book", rows: rows)]
        )
    }

    private func renderFB2(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxXML) ?? Data()
        guard let document = try? XMLDocument(data: data) else {
            throw PreviewError.corruptFile("invalid FB2 XML")
        }
        func first(_ xpath: String) -> String? {
            (try? document.nodes(forXPath: xpath).first?.stringValue)?
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        var rows: [KeyValueRow] = []
        if let title = first("//*[local-name()='book-title']") { rows.append(KeyValueRow("Title", title)) }
        let firstName = first("//*[local-name()='author']/*[local-name()='first-name']") ?? ""
        let lastName = first("//*[local-name()='author']/*[local-name()='last-name']") ?? ""
        let author = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        if !author.isEmpty { rows.append(KeyValueRow("Author", author)) }
        if let genre = first("//*[local-name()='genre']") { rows.append(KeyValueRow("Genre", genre)) }
        if let language = first("//*[local-name()='lang']") { rows.append(KeyValueRow("Language", language)) }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "FictionBook eBook",
            iconSystemName: "book.closed",
            sections: [.keyValues(title: "Book", rows: rows)]
        )
    }
}
