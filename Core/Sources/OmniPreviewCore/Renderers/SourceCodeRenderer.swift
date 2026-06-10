import Foundation

/// Plain-text source preview with encoding detection, line count, and
/// language identification. Syntax highlighting is a planned enhancement.
public struct SourceCodeRenderer: PreviewRenderer {
    public static let id = "source-code"
    public static let displayName = "Source Code"

    static let maxReadBytes = 2 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .sourceCode = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .sourceCode(let language) = file.kind else {
            throw PreviewError.unsupportedType
        }

        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxReadBytes) ?? Data()
        let truncated = file.fileSize > UInt64(data.count)

        var usedEncoding: String.Encoding = .utf8
        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = utf8
        } else {
            var converted: NSString?
            let rawEncoding = NSString.stringEncoding(
                for: data, encodingOptions: nil,
                convertedString: &converted, usedLossyConversion: nil
            )
            if rawEncoding != 0, let converted {
                content = converted as String
                usedEncoding = String.Encoding(rawValue: rawEncoding)
            } else {
                // Undetectable encoding: decode lossily rather than fail.
                content = String(decoding: data, as: UTF8.self)
            }
        }

        let lineCount = content.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }

        var rows = [
            KeyValueRow("Language", language),
            KeyValueRow("Lines", "\(lineCount)\(truncated ? "+ (truncated)" : "")"),
            KeyValueRow("Encoding", encodingName(usedEncoding)),
            KeyValueRow("Size", Format.bytes(file.fileSize)),
        ]
        if truncated {
            rows.append(KeyValueRow("Note", "Showing first \(Format.bytes(UInt64(data.count)))"))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: language,
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            sections: [
                .keyValues(title: nil, rows: rows),
                .text(content: content, language: language),
            ]
        )
    }

    private func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: return "UTF-16"
        case .ascii: return "ASCII"
        case .isoLatin1: return "ISO Latin 1"
        default: return "Other (\(encoding.rawValue))"
        }
    }
}
