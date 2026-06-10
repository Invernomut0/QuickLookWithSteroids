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
}
