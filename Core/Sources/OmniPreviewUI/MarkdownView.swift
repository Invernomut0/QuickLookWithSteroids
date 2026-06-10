import SwiftUI
import AppKit

/// Renders a Markdown string as a native SwiftUI view — no WebView, no
/// third-party dependencies. Handles: ATX headings, fenced code blocks
/// (with syntax highlighting), bullet and ordered lists, blockquotes,
/// horizontal rules, tables, and paragraphs. Inline formatting
/// (bold, italic, inline code, links) is handled by `AttributedString(markdown:)`.
struct MarkdownView: View {
    let source: String

    var body: some View {
        let blocks = MarkdownParser.parse(source)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }
}

// MARK: Block model

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case unorderedItem(text: String, depth: Int)
    case orderedItem(number: Int, text: String, depth: Int)
    case blockquote(text: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
    case blankSpace
}

// MARK: Parser

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ATX heading: # to ######
            if let heading = parseATXHeading(trimmed) {
                blocks.append(heading); index += 1; continue
            }

            // Fenced code block: ``` or ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { index += 1; break }
                    code.append(lines[index]); index += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang,
                                          code: code.joined(separator: "\n")))
                continue
            }

            // Horizontal rule: ---, ***, ___
            if ["-", "*", "_"].contains(String(trimmed.prefix(1))),
               trimmed.unicodeScalars.allSatisfy({ "-*_ ".unicodeScalars.contains($0) }),
               trimmed.filter({ !$0.isWhitespace }).count >= 3 {
                blocks.append(.horizontalRule); index += 1; continue
            }

            // Unordered list item
            if let listDepth = listDepth(line, markers: ["-", "*", "+"]) {
                let text = String(trimmed.dropFirst(2))
                blocks.append(.unorderedItem(text: text, depth: listDepth))
                index += 1; continue
            }

            // Ordered list item: "1. text"
            if let (number, text) = parseOrderedItem(trimmed) {
                let depth = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                blocks.append(.orderedItem(number: number, text: text, depth: depth))
                index += 1; continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var lines_: [String] = [String(trimmed.dropFirst().drop(while: { $0 == " " }))]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix(">") {
                        lines_.append(String(next.dropFirst().drop(while: { $0 == " " })))
                        index += 1
                    } else if next.isEmpty { break }
                    else { break }
                }
                blocks.append(.blockquote(text: lines_.joined(separator: "\n")))
                continue
            }

            // Table: | col | col |
            if trimmed.hasPrefix("|") || trimmed.contains(" | ") {
                if let table = parseTable(lines: lines, startIndex: &index) {
                    blocks.append(table); continue
                }
            }

            // Setext heading: underlined with === or ---
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && next.allSatisfy({ $0 == "=" || $0 == "-" }) && next.count >= 2 {
                    let level = next.first == "=" ? 1 : 2
                    blocks.append(.heading(level: level, text: trimmed))
                    index += 2; continue
                }
            }

            // Blank line
            if trimmed.isEmpty {
                if blocks.last.map({ if case .blankSpace = $0 { false } else { true } }) ?? true {
                    blocks.append(.blankSpace)
                }
                index += 1; continue
            }

            // Paragraph: accumulate until blank line or block-level element
            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if nextTrimmed.hasPrefix("```") || nextTrimmed.hasPrefix("~~~") { break }
                if parseATXHeading(nextTrimmed) != nil { break }
                if nextTrimmed.hasPrefix(">") { break }
                paragraphLines.append(next)
                index += 1
            }
            let joined = paragraphLines.joined(separator: "\n")
            blocks.append(.paragraph(text: joined))
        }

        // Trim leading/trailing blank lines
        return blocks.filter {
            if case .blankSpace = $0 { return false }; return true
        }
    }

    private static func parseATXHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level <= 6, line.count > level else { return nil }
        let afterHash = line.dropFirst(level)
        guard afterHash.first == " " || afterHash.isEmpty else { return nil }
        let text = afterHash.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func listDepth(_ line: String, markers: [String]) -> Int? {
        let spaces = line.prefix(while: { $0 == " " }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in markers {
            if trimmed.hasPrefix(marker + " ") || trimmed.hasPrefix(marker + "\t") {
                return spaces / 2
            }
        }
        return nil
    }

    private static func parseOrderedItem(_ trimmed: String) -> (Int, String)? {
        let pattern = #"^(\d+)\.\s+(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let numRange = Range(match.range(at: 1), in: trimmed),
              let textRange = Range(match.range(at: 2), in: trimmed),
              let number = Int(trimmed[numRange]) else { return nil }
        return (number, String(trimmed[textRange]))
    }

    private static func parseTable(lines: [String], startIndex: inout Int) -> MarkdownBlock? {
        guard startIndex + 1 < lines.count else { return nil }
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard separatorLine.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }) else { return nil }

        func cells(_ line: String) -> [String] {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.first?.isEmpty == true { parts.removeFirst() }
            if parts.last?.isEmpty == true { parts.removeLast() }
            return parts
        }

        let headers = cells(headerLine)
        guard !headers.isEmpty else { return nil }
        startIndex += 2

        var rows: [[String]] = []
        while startIndex < lines.count {
            let row = lines[startIndex].trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("|") || row.contains("|") else { break }
            rows.append(cells(row))
            startIndex += 1
        }
        return .table(headers: headers, rows: rows)
    }
}

// MARK: Block view

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        Group {
            switch block {
            case .heading(let level, let text):
                HeadingView(level: level, text: text)
                    .padding(.top, level <= 2 ? 16 : 10)
                    .padding(.bottom, 4)

            case .paragraph(let text):
                inlineText(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)

            case .codeBlock(let language, let code):
                CodeBlockView(code: code, language: language)
                    .padding(.vertical, 8)

            case .unorderedItem(let text, let depth):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .center)
                    inlineText(text)
                }
                .padding(.leading, CGFloat(depth) * 20)
                .padding(.vertical, 1)

            case .orderedItem(let number, let text, let depth):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(number).")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    inlineText(text)
                }
                .padding(.leading, CGFloat(depth) * 20)
                .padding(.vertical, 1)

            case .blockquote(let text):
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 3)
                        .cornerRadius(1.5)
                    inlineText(text)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
                .padding(.vertical, 6)

            case .horizontalRule:
                Divider().padding(.vertical, 12)

            case .table(let headers, let rows):
                TableView(headers: headers, rows: rows)
                    .padding(.vertical, 8)

            case .blankSpace:
                Spacer().frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineText(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.body)
        } else {
            Text(markdown)
                .font(.body)
        }
    }
}

// MARK: Heading

private struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(headingFont)
                .fontWeight(level <= 2 ? .bold : .semibold)
                .fixedSize(horizontal: false, vertical: true)
            if level <= 2 {
                Divider()
            }
        }
    }

    private var headingFont: Font {
        switch level {
        case 1: return .system(size: 26)
        case 2: return .system(size: 21)
        case 3: return .system(size: 17)
        case 4: return .system(size: 15)
        default: return .system(size: 13)
        }
    }
}

// MARK: Code block

private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge
            if let language, !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    Spacer()
                }
                .background(Color(nsColor: .separatorColor).opacity(0.5))
            }
            let attributed = SyntaxHighlighter.highlight(code, language: language, fontSize: 12)
            let height = CodeView.estimatedHeight(for: code)
            CodeView(attributedString: attributed, maxHeight: height)
                .frame(height: height)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

// MARK: Table

private struct TableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .border(Color(nsColor: .separatorColor), width: 0.5)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            let text: String = colIdx < row.count ? cell : ""
                            Text(text)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(rowIdx % 2 == 0
                                    ? Color.clear
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .border(Color(nsColor: .separatorColor), width: 0.5)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
