import Foundation
import CoreText

/// Font metadata via CoreText; the UI layer renders the live specimen
/// from the `fontSpecimen` section.
public struct FontRenderer: PreviewRenderer {
    public static let id = "font"
    public static let displayName = "Font"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .font }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file.url as CFURL) as? [CTFontDescriptor],
              !descriptors.isEmpty else {
            // CoreText cannot open WOFF containers; fall back to header metadata.
            if let woff = try Self.woffDocument(file) { return woff }
            throw PreviewError.corruptFile("CoreText could not parse this font")
        }

        var sections: [PreviewSection] = []
        for descriptor in descriptors.prefix(10) {
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            var rows = [
                KeyValueRow("Family", CTFontCopyFamilyName(font) as String),
                KeyValueRow("Style", CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? "—"),
                KeyValueRow("PostScript name", CTFontCopyPostScriptName(font) as String),
                KeyValueRow("Glyphs", "\(CTFontGetGlyphCount(font))"),
            ]
            if let version = CTFontCopyName(font, kCTFontVersionNameKey) as String? {
                rows.append(KeyValueRow("Version", version))
            }
            sections.append(.keyValues(title: CTFontCopyFullName(font) as String, rows: rows))
        }
        sections.append(.fontSpecimen(fontURL: file.url))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: descriptors.count == 1 ? "Font" : "Font Collection (\(descriptors.count) faces)",
            iconSystemName: "textformat",
            sections: sections
        )
    }

    /// WOFF/WOFF2 header metadata (big-endian): flavor, table count,
    /// uncompressed sfnt size.
    static func woffDocument(_ file: DetectedFile) throws -> PreviewDocument? {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 48) ?? Data()
        guard head.starts(with: Array("wOFF".utf8)) || head.starts(with: Array("wOF2".utf8)) else {
            return nil
        }
        let isWOFF2 = head.starts(with: Array("wOF2".utf8))
        var reader = DataReader(head)
        try reader.skip(4)
        let flavor = try reader.readString(4)
        try reader.skip(4) // total length
        let numTables = try reader.readU16LE().byteSwapped
        try reader.skip(2)
        let sfntSize = try reader.readU32BE()

        let flavorName = flavor == "OTTO" ? "OpenType (CFF)" : flavor == "ttcf" ? "TrueType Collection" : "TrueType"
        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: isWOFF2 ? "WOFF2 Web Font" : "WOFF Web Font",
            iconSystemName: "textformat",
            sections: [.keyValues(title: "Web Font", rows: [
                KeyValueRow("Wrapped format", flavorName),
                KeyValueRow("Tables", "\(numTables)"),
                KeyValueRow("Uncompressed size", Format.bytes(UInt64(sfntSize))),
                KeyValueRow("File size", Format.bytes(file.fileSize)),
                KeyValueRow("Note", "Specimen requires sfnt unwrapping (planned)"),
            ])]
        )
    }
}
