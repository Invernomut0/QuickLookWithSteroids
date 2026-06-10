import Foundation

/// Office document previews: OOXML (DOCX/XLSX/PPTX) via docProps, and
/// OpenDocument (ODT/ODS/ODP) via meta.xml. Both are ZIP containers.
public struct OfficeRenderer: PreviewRenderer {
    public static let id = "office"
    public static let displayName = "Office Documents"

    static let ooxml: [String: String] = [
        "docx": "Word Document", "xlsx": "Excel Workbook", "pptx": "PowerPoint Presentation",
    ]
    static let openDocument: [String: String] = [
        "odt": "OpenDocument Text", "ods": "OpenDocument Spreadsheet", "odp": "OpenDocument Presentation",
    ]
    static let maxXML = 4 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        guard file.kind == .zip else { return false }
        return Self.ooxml.keys.contains(file.pathExtension)
            || Self.openDocument.keys.contains(file.pathExtension)
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        if let label = Self.ooxml[file.pathExtension] {
            return try renderOOXML(file, archive: archive, label: label)
        }
        if let label = Self.openDocument[file.pathExtension] {
            return try renderODF(file, archive: archive, label: label)
        }
        throw PreviewError.unsupportedType
    }

    private func xml(_ archive: ZIPArchive, _ path: String) -> XMLDocument? {
        guard let entry = archive.entry(at: path),
              let data = try? archive.extract(entry, maxBytes: Self.maxXML) else { return nil }
        return try? XMLDocument(data: data)
    }

    private func renderOOXML(_ file: DetectedFile, archive: ZIPArchive, label: String) throws -> PreviewDocument {
        var rows: [KeyValueRow] = []

        if let core = xml(archive, "docProps/core.xml") {
            func value(_ element: String) -> String? {
                (try? core.nodes(forXPath: "//*[local-name()='\(element)']").first?.stringValue)?
                    .flatMap { $0.isEmpty ? nil : $0 }
            }
            if let title = value("title") { rows.append(KeyValueRow("Title", title)) }
            if let creator = value("creator") { rows.append(KeyValueRow("Author", creator)) }
            if let modifiedBy = value("lastModifiedBy") { rows.append(KeyValueRow("Last modified by", modifiedBy)) }
            if let modified = value("modified") { rows.append(KeyValueRow("Modified", modified)) }
        }

        var statRows: [KeyValueRow] = []
        if let app = xml(archive, "docProps/app.xml") {
            func value(_ element: String) -> String? {
                (try? app.nodes(forXPath: "//*[local-name()='\(element)']").first?.stringValue)?
                    .flatMap { $0.isEmpty ? nil : $0 }
            }
            let labels: [(String, String)] = [
                ("Pages", "Pages"), ("Words", "Words"), ("Slides", "Slides"),
                ("Application", "Application"),
            ]
            for (element, label) in labels {
                if let v = value(element) { statRows.append(KeyValueRow(label, v)) }
            }
        }

        // Sheet names for workbooks, slide count fallback for presentations.
        if file.pathExtension == "xlsx", let workbook = xml(archive, "xl/workbook.xml") {
            let names = (try? workbook.nodes(forXPath: "//*[local-name()='sheet']/@name"))?
                .compactMap(\.stringValue) ?? []
            if !names.isEmpty {
                statRows.append(KeyValueRow("Sheets", "\(names.count): " + names.prefix(12).joined(separator: ", ")))
            }
        }
        if file.pathExtension == "pptx", !statRows.contains(where: { $0.key == "Slides" }) {
            let slides = archive.entries.filter {
                $0.path.hasPrefix("ppt/slides/slide") && $0.path.hasSuffix(".xml")
            }
            statRows.append(KeyValueRow("Slides", "\(slides.count)"))
        }

        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        var sections: [PreviewSection] = [.keyValues(title: "Document", rows: rows)]
        if !statRows.isEmpty {
            sections.append(.keyValues(title: "Statistics", rows: statRows))
        }
        if let thumbnail = archive.firstEntry(withSuffix: "thumbnail.jpeg")
            ?? archive.firstEntry(withSuffix: "thumbnail.png"),
           let data = try? archive.extract(thumbnail, maxBytes: 8 * 1024 * 1024) {
            sections.insert(.imageData(data), at: 0)
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: label,
            iconSystemName: icon(for: file.pathExtension),
            sections: sections
        )
    }

    private func renderODF(_ file: DetectedFile, archive: ZIPArchive, label: String) throws -> PreviewDocument {
        var rows: [KeyValueRow] = []
        if let meta = xml(archive, "meta.xml") {
            func value(_ element: String) -> String? {
                (try? meta.nodes(forXPath: "//*[local-name()='\(element)']").first?.stringValue)?
                    .flatMap { $0.isEmpty ? nil : $0 }
            }
            if let title = value("title") { rows.append(KeyValueRow("Title", title)) }
            if let creator = value("creator") { rows.append(KeyValueRow("Author", creator)) }
            if let date = value("date") { rows.append(KeyValueRow("Modified", date)) }
            if let generator = value("generator") { rows.append(KeyValueRow("Application", generator)) }
            // Document statistics are attributes on office:document-statistic.
            if let stats = try? meta.nodes(forXPath: "//*[local-name()='document-statistic']").first as? XMLElement {
                for attribute in stats.attributes ?? [] {
                    if let name = attribute.localName, let v = attribute.stringValue {
                        rows.append(KeyValueRow(name.replacingOccurrences(of: "-", with: " ").capitalized, v))
                    }
                }
            }
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        var sections: [PreviewSection] = [.keyValues(title: "Document", rows: rows)]
        if let thumbnail = archive.entry(at: "Thumbnails/thumbnail.png"),
           let data = try? archive.extract(thumbnail, maxBytes: 8 * 1024 * 1024) {
            sections.insert(.imageData(data), at: 0)
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: label,
            iconSystemName: icon(for: file.pathExtension),
            sections: sections
        )
    }

    private func icon(for ext: String) -> String {
        switch ext {
        case "docx", "odt": return "doc.text"
        case "xlsx", "ods": return "tablecells"
        case "pptx", "odp": return "rectangle.on.rectangle"
        default: return "doc"
        }
    }
}
