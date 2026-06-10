import Foundation
import PDFKit

/// Enhanced PDF metadata: document info, page count and sizes, outline,
/// encryption status.
public struct PDFRenderer: PreviewRenderer {
    public static let id = "pdf"
    public static let displayName = "PDF Document"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .pdf }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard let document = PDFDocument(url: file.url) else {
            throw PreviewError.corruptFile("PDFKit could not open this document")
        }

        var rows = [
            KeyValueRow("Pages", "\(document.pageCount)"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if let page = document.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            rows.append(KeyValueRow("Page size", String(format: "%.0f × %.0f pt", bounds.width, bounds.height)))
        }
        if document.isEncrypted {
            rows.append(KeyValueRow("Encrypted", document.isLocked ? "Yes (locked)" : "Yes"))
        }

        var infoRows: [KeyValueRow] = []
        let attributes = document.documentAttributes ?? [:]
        let labels: [(PDFDocumentAttribute, String)] = [
            (.titleAttribute, "Title"), (.authorAttribute, "Author"),
            (.subjectAttribute, "Subject"), (.creatorAttribute, "Creator"),
            (.producerAttribute, "Producer"),
        ]
        for (attribute, label) in labels {
            if let value = attributes[attribute] as? String, !value.isEmpty {
                infoRows.append(KeyValueRow(label, value))
            }
        }
        if let created = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
            infoRows.append(KeyValueRow("Created", Format.date(created)))
        }
        if let modified = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date {
            infoRows.append(KeyValueRow("Modified", Format.date(modified)))
        }

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: rows)]
        if !infoRows.isEmpty {
            sections.append(.keyValues(title: "Document Info", rows: infoRows))
        }
        if let outline = document.outlineRoot, outline.numberOfChildren > 0 {
            sections.append(.keyValues(title: "Bookmarks", rows: Self.outlineRows(outline)))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "PDF Document — \(document.pageCount) pages",
            iconSystemName: "doc.richtext",
            sections: sections
        )
    }

    private static func outlineRows(_ root: PDFOutline, limit: Int = 50) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        for index in 0..<root.numberOfChildren {
            guard rows.count < limit, let child = root.child(at: index) else { break }
            let page = child.destination?.page
            let pageLabel = page.flatMap { $0.document?.index(for: $0) }.map { "p. \($0 + 1)" } ?? ""
            rows.append(KeyValueRow(child.label ?? "—", pageLabel))
        }
        return rows
    }
}
