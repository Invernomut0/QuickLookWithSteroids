import Foundation

/// Structured INI / CFG preview: parses `[Section]` headers and `key = value`
/// pairs. Handles both `=` and `:` as delimiters and strips inline comments.
/// Registered before the generic source-code renderer.
public struct INIRenderer: PreviewRenderer {
    public static let id = "ini"
    public static let displayName = "Configuration File"

    static let maxReadBytes = 2 * 1024 * 1024
    static let extensions: Set<String> = ["ini", "cfg", "conf", "cnf", "properties", "desktop", "editorconfig", "gitconfig"]

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if file.kind == .sourceCode(language: "INI") || Self.extensions.contains(file.pathExtension) {
            return true
        }
        // Extensionless config files (or uncommon config extensions) should
        // still be handled here when they look like INI syntax.
        return Self.looksLikeINI(url: file.url)
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxReadBytes) ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        let parsed = Self.parse(text)

        var summary = [
            KeyValueRow("Sections", "\(parsed.sections.count)"),
            KeyValueRow("Total keys", "\(parsed.sections.values.map(\.count).reduce(0, +))"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if !LicenseManager.shared.isProUnlocked {
            summary.append(KeyValueRow("PRO", "Unlock syntax highlighting & formatted raw config view"))
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary.append(KeyValueRow("Status", "Empty configuration file"))
        }
        if data.count < Int(file.fileSize) {
            summary.append(KeyValueRow("Note", "Showing first \(Format.bytes(UInt64(data.count)))"))
        }

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: summary)]

        // Keep a raw-text section so Pro users get syntax highlighting and
        // formatting parity with other text-based formats.
        let highlightLanguage: String
        switch file.pathExtension.lowercased() {
        case "cfg": highlightLanguage = "cfg"
        case "conf", "cnf": highlightLanguage = "conf"
        default: highlightLanguage = "ini"
        }
        sections.append(.text(content: text, language: highlightLanguage))

        // Global keys first (no section header), then named sections in order.
        for sectionName in parsed.order {
            guard let rows = parsed.sections[sectionName], !rows.isEmpty else { continue }
            let title = sectionName.isEmpty ? "General" : "[\(sectionName)]"
            sections.append(.keyValues(title: title, rows: rows))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Configuration File",
            iconSystemName: "doc.badge.gearshape",
            sections: sections
        )
    }

    // MARK: Parser

    struct Parsed {
        var sections: [String: [KeyValueRow]] = [:]
        var order: [String] = []
    }

    static func parse(_ text: String) -> Parsed {
        var result = Parsed()
        var current = ""
        result.sections[""] = []
        result.order = [""]

        // Handle multi-line values ending with a trailing backslash.
        var logicalLines: [String] = []
        var buffer = ""
        for line in text.components(separatedBy: .newlines) {
            if buffer.isEmpty {
                buffer = line
            } else {
                buffer += "\n" + line
            }
            if buffer.hasSuffix("\\") {
                buffer.removeLast()
                continue
            }
            logicalLines.append(buffer)
            buffer = ""
        }
        if !buffer.isEmpty { logicalLines.append(buffer) }

        for (index, rawLine) in logicalLines.enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if index == 0, line.hasPrefix("\u{FEFF}") {
                line.removeFirst()
            }

            // Skip blank lines and comments
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("!") { continue }

            // Section header
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let name = String(line[line.index(after: line.startIndex)..<close])
                current = name
                if result.sections[name] == nil {
                    result.sections[name] = []
                    result.order.append(name)
                }
                continue
            }

            // Key = value  or  key: value
            var delimiter: Character = "="
            if !line.contains("="), line.contains(":") { delimiter = ":" }
            guard let delimIndex = line.firstIndex(of: delimiter) else { continue }

            let key = line[..<delimIndex].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: delimIndex)...].trimmingCharacters(in: .whitespaces)

            // Strip inline comments (but not inside quotes)
            value = stripInlineComment(value)

            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            guard !key.isEmpty else { continue }
            result.sections[current, default: []].append(KeyValueRow(key, value))
        }

        // Remove empty sections
        result.order = result.order.filter { !(result.sections[$0]?.isEmpty ?? true) }
        return result
    }

    private static func stripInlineComment(_ value: String) -> String {
        var inQuote = false
        var quoteChar: Character = "\0"
        for (index, char) in value.enumerated() {
            if !inQuote, (char == "\"" || char == "'") {
                inQuote = true; quoteChar = char
            } else if inQuote, char == quoteChar {
                inQuote = false
            } else if !inQuote, char == ";" || char == "#" {
                return String(value.prefix(index)).trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    private static func looksLikeINI(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 32 * 1024),
              !data.isEmpty else { return false }
        defer { try? handle.close() }

        guard FileTypeDetector.looksLikeTextSample(data) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: .newlines)

        var sectionCount = 0
        var keyValueCount = 0
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("!") { continue }

            if line.hasPrefix("["), line.contains("]") {
                sectionCount += 1
                continue
            }

            var delimiter: Character = "="
            if !line.contains("="), line.contains(":") { delimiter = ":" }
            if let idx = line.firstIndex(of: delimiter) {
                let key = line[..<idx].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    keyValueCount += 1
                }
            }
        }

        // Avoid false positives on random text: require at least two pairs
        // and either one section or multiple key/value lines.
        return keyValueCount >= 2 && (sectionCount >= 1 || keyValueCount >= 3)
    }
}
