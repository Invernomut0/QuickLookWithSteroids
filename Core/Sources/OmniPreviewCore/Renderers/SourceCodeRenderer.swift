import Foundation

/// Plain-text source preview with encoding detection, line count, and
/// language identification. Syntax highlighting is a planned enhancement.
public struct SourceCodeRenderer: PreviewRenderer {
    public static let id = "source-code"
    public static let displayName = "Source Code"

    static let maxReadBytes = 2 * 1024 * 1024
    /// How many bytes to sniff when deciding whether an unknown file is text.
    static let sniffBytes = 8 * 1024
    /// Max fraction of non-printable bytes before a file is considered binary.
    static let binaryThreshold = 0.30

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .sourceCode = file.kind { return true }
        if file.kind == .unknown { return Self.looksLikeText(url: file.url) }
        return false
    }

    /// Reads the first `sniffBytes` and returns true when the content looks
    /// like human-readable text: no null bytes and fewer than `binaryThreshold`
    /// non-printable characters.
    static func looksLikeText(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let sample = try? handle.read(upToCount: sniffBytes),
              !sample.isEmpty else { return false }
        defer { try? handle.close() }
        let bytes = [UInt8](sample)
        if bytes.contains(0x00) { return false }
        let nonPrintable = bytes.filter { $0 < 0x09 || ($0 > 0x0D && $0 < 0x20 && $0 != 0x1B) }.count
        return Double(nonPrintable) / Double(bytes.count) < binaryThreshold
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let language: String
        if case .sourceCode(let lang) = file.kind {
            language = lang
        } else {
            language = "Plain Text"
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

        let isPlainText = language == "Plain Text"
        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: language,
            iconSystemName: isPlainText ? "doc.text" : "chevron.left.forwardslash.chevron.right",
            sections: [
                .keyValues(title: nil, rows: rows),
                .text(content: content, language: isPlainText ? nil : language),
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
