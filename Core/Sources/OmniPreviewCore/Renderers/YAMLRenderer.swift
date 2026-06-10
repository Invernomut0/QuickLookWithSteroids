import Foundation

/// Structured YAML preview: recognizes Kubernetes manifests, Docker Compose
/// files, and GitHub Actions workflows, and summarizes top-level structure.
/// Registered ahead of the plain source-code renderer.
public struct YAMLRenderer: PreviewRenderer {
    public static let id = "yaml"
    public static let displayName = "YAML"

    static let maxRead = 4 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        file.kind == .sourceCode(language: "YAML")
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxRead) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: "\n")

        let analysis = Self.analyze(lines: lines, path: file.url.path)
        var rows = [KeyValueRow("Type", analysis.flavor)]
        rows.append(contentsOf: analysis.rows)
        if analysis.documents > 1 {
            rows.append(KeyValueRow("Documents", "\(analysis.documents)"))
        }
        if !analysis.topLevelKeys.isEmpty {
            rows.append(KeyValueRow("Top-level keys", analysis.topLevelKeys.prefix(15).joined(separator: ", ")))
        }
        rows.append(KeyValueRow("Lines", "\(lines.count)"))
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: analysis.flavor,
            iconSystemName: analysis.icon,
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .text(content: text, language: "YAML"),
            ]
        )
    }

    struct Analysis {
        var flavor: String
        var icon: String
        var rows: [KeyValueRow]
        var documents: Int
        var topLevelKeys: [String]
    }

    static func analyze(lines: [String], path: String) -> Analysis {
        let documents = lines.filter { $0.hasPrefix("---") }.count + 1
        let topLevelKeys = lines.compactMap { line -> String? in
            guard let first = line.first, first.isLetter || first == "_" || first == "\"",
                  let colon = line.firstIndex(of: ":") else { return nil }
            return String(line[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        func values(of key: String) -> [String] {
            lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(key + ":") else { return nil }
                let value = trimmed.dropFirst(key.count + 1)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                return value.isEmpty ? nil : value
            }
        }

        // Kubernetes manifest: apiVersion + kind at the top level.
        if topLevelKeys.contains("apiVersion"), topLevelKeys.contains("kind") {
            var rows: [KeyValueRow] = []
            let kinds = values(of: "kind")
            rows.append(KeyValueRow("Resources", kinds.prefix(10).joined(separator: ", ")))
            let names = values(of: "name")
            if let name = names.first { rows.append(KeyValueRow("Name", name)) }
            if let namespace = values(of: "namespace").first {
                rows.append(KeyValueRow("Namespace", namespace))
            }
            let images = values(of: "image")
            if !images.isEmpty {
                rows.append(KeyValueRow("Images", images.prefix(5).joined(separator: ", ")))
            }
            return Analysis(flavor: "Kubernetes Manifest", icon: "helm",
                            rows: rows, documents: documents, topLevelKeys: topLevelKeys)
        }

        // Docker Compose: a top-level services: block.
        if topLevelKeys.contains("services") {
            let services = Self.childKeys(of: "services", in: lines)
            var rows = [KeyValueRow("Services", services.prefix(15).joined(separator: ", "))]
            let images = values(of: "image")
            if !images.isEmpty {
                rows.append(KeyValueRow("Images", images.prefix(8).joined(separator: ", ")))
            }
            if topLevelKeys.contains("volumes") {
                rows.append(KeyValueRow("Volumes", Self.childKeys(of: "volumes", in: lines).joined(separator: ", ")))
            }
            return Analysis(flavor: "Docker Compose", icon: "shippingbox",
                            rows: rows, documents: documents, topLevelKeys: topLevelKeys)
        }

        // GitHub Actions workflow: jobs + on/name, or located in .github/workflows.
        if topLevelKeys.contains("jobs"),
           topLevelKeys.contains("on") || topLevelKeys.contains("name") || path.contains(".github/workflows") {
            let jobs = Self.childKeys(of: "jobs", in: lines)
            var rows = [KeyValueRow("Jobs", jobs.prefix(15).joined(separator: ", "))]
            if let name = values(of: "name").first { rows.insert(KeyValueRow("Workflow", name), at: 0) }
            let steps = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- name:")
                || $0.trimmingCharacters(in: .whitespaces).hasPrefix("- uses:") }.count
            if steps > 0 { rows.append(KeyValueRow("Steps", "\(steps)")) }
            return Analysis(flavor: "GitHub Actions Workflow", icon: "gearshape.2",
                            rows: rows, documents: documents, topLevelKeys: topLevelKeys)
        }

        return Analysis(flavor: "YAML Document", icon: "doc.text",
                        rows: [], documents: documents, topLevelKeys: topLevelKeys)
    }

    /// Names of the keys nested one level under a given top-level block.
    static func childKeys(of parent: String, in lines: [String]) -> [String] {
        var keys: [String] = []
        var inBlock = false
        for line in lines {
            if line.hasPrefix(parent + ":") { inBlock = true; continue }
            guard inBlock else { continue }
            // A new top-level key ends the block.
            if let first = line.first, first.isLetter || first == "_" { break }
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, trimmed.hasSuffix(":"), !trimmed.hasPrefix("-"), !trimmed.hasPrefix("#") {
                keys.append(String(trimmed.dropLast()))
            }
        }
        return keys
    }
}
