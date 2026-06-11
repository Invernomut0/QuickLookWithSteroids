import Foundation

/// GIS formats: GeoJSON feature statistics, KML/KMZ placemark counts,
/// Shapefile header (shape type + bounding box).
public struct GeoRenderer: PreviewRenderer {
    public static let id = "geo"
    public static let displayName = "GIS Files"

    static let maxRead = 64 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .geo = file.kind { return true }
        return file.kind == .zip && file.pathExtension == "kmz"
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        if file.kind == .zip {
            return try renderKMZ(file)
        }
        guard case .geo(let format) = file.kind else { throw PreviewError.unsupportedType }
        switch format {
        case "GeoJSON": return try renderGeoJSON(file)
        case "KML":
            let data = try boundedRead(file)
            return try renderKML(file, data: data, subtitle: "KML Document")
        case "Shapefile": return try renderShapefile(file)
        default: throw PreviewError.unsupportedType
        }
    }

    private func boundedRead(_ file: DetectedFile) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        return try handle.read(upToCount: Self.maxRead) ?? Data()
    }

    private func renderGeoJSON(_ file: DetectedFile) throws -> PreviewDocument {
        let data = try boundedRead(file)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            throw PreviewError.corruptFile("invalid GeoJSON")
        }

        var rows = [KeyValueRow("Type", type)]
        if let features = json["features"] as? [[String: Any]] {
            rows.append(KeyValueRow("Features", "\(features.count)"))
            var geometryCounts: [String: Int] = [:]
            for feature in features.prefix(10_000) {
                let geometryType = (feature["geometry"] as? [String: Any])?["type"] as? String ?? "null"
                geometryCounts[geometryType, default: 0] += 1
            }
            for (geometry, count) in geometryCounts.sorted(by: { $0.value > $1.value }) {
                rows.append(KeyValueRow(geometry, "\(count)"))
            }
            // Property keys from the first feature hint at the schema.
            if let properties = features.first?["properties"] as? [String: Any], !properties.isEmpty {
                rows.append(KeyValueRow("Properties", properties.keys.sorted().prefix(12).joined(separator: ", ")))
            }
        }
        if let bbox = json["bbox"] as? [Double], bbox.count >= 4 {
            rows.append(KeyValueRow("Bounding box", bbox.map { String(format: "%.4f", $0) }.joined(separator: ", ")))
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "GeoJSON",
            iconSystemName: "map",
            sections: [.keyValues(title: "GeoJSON", rows: rows)]
        )
    }

    private func renderKML(_ file: DetectedFile, data: Data, subtitle: String) throws -> PreviewDocument {
        guard let document = try? XMLDocument(data: data) else {
            let textPreview = String(data: data.prefix(8 * 1024), encoding: .utf8)
            var rows: [KeyValueRow] = [
                KeyValueRow("File size", Format.bytes(file.fileSize)),
                KeyValueRow("Note", "Invalid or empty KML XML. Showing raw text preview when available."),
            ]
            if data.isEmpty {
                rows.append(KeyValueRow("Status", "Empty file"))
            }
            var sections: [PreviewSection] = [.keyValues(title: "Map Data", rows: rows)]
            if let textPreview, !textPreview.isEmpty {
                sections.append(.text(content: textPreview, language: "XML"))
            }
            return PreviewDocument(
                title: file.url.lastPathComponent,
                subtitle: subtitle,
                iconSystemName: "map",
                sections: sections
            )
        }
        var rows: [KeyValueRow] = []
        if let name = try? document.nodes(forXPath: "//*[local-name()='Document']/*[local-name()='name']").first?.stringValue,
           !name.isEmpty {
            rows.append(KeyValueRow("Name", name))
        }
        let counts: [(String, String)] = [
            ("Placemark", "Placemarks"), ("Folder", "Folders"),
            ("Point", "Points"), ("LineString", "Lines"), ("Polygon", "Polygons"),
        ]
        for (element, label) in counts {
            let count = (try? document.nodes(forXPath: "//*[local-name()='\(element)']").count) ?? 0
            if count > 0 { rows.append(KeyValueRow(label, "\(count)")) }
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: subtitle,
            iconSystemName: "map",
            sections: [.keyValues(title: "Map Data", rows: rows)]
        )
    }

    private func renderKMZ(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        guard let kmlEntry = archive.firstEntry(withSuffix: ".kml"),
              let data = try? archive.extract(kmlEntry, maxBytes: Self.maxRead) else {
            throw PreviewError.corruptFile("KMZ contains no KML document")
        }
        return try renderKML(file, data: data, subtitle: "KMZ (compressed KML)")
    }

    /// Shapefile main file header: big-endian length, little-endian shape
    /// type and bounding box.
    private func renderShapefile(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 100) ?? Data()
        guard head.count >= 100 else { throw PreviewError.corruptFile("truncated shapefile header") }

        var reader = DataReader(head)
        try reader.skip(32)
        let shapeType = try reader.readU32LE()
        func double(_ r: inout DataReader) throws -> Double {
            Double(bitPattern: try r.readU64LE())
        }
        let minX = try double(&reader)
        let minY = try double(&reader)
        let maxX = try double(&reader)
        let maxY = try double(&reader)

        let shapeNames: [UInt32: String] = [
            0: "Null", 1: "Point", 3: "PolyLine", 5: "Polygon", 8: "MultiPoint",
            11: "PointZ", 13: "PolyLineZ", 15: "PolygonZ", 18: "MultiPointZ",
            21: "PointM", 23: "PolyLineM", 25: "PolygonM", 28: "MultiPointM", 31: "MultiPatch",
        ]

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "ESRI Shapefile",
            iconSystemName: "map",
            sections: [.keyValues(title: "Shapefile", rows: [
                KeyValueRow("Shape type", shapeNames[shapeType] ?? "type \(shapeType)"),
                KeyValueRow("Bounding box", String(format: "%.4f, %.4f → %.4f, %.4f", minX, minY, maxX, maxY)),
                KeyValueRow("File size", Format.bytes(file.fileSize)),
            ])]
        )
    }
}

/// Database dumps (PostgreSQL/MySQL) and Terraform state files.
public struct DumpRenderer: PreviewRenderer {
    public static let id = "dump"
    public static let displayName = "Database Dumps & State Files"

    static let maxRead = 8 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        switch file.kind {
        case .sqlDump, .terraformState: return true
        default: return false
        }
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxRead) ?? Data()

        if file.kind == .terraformState {
            return try renderTerraformState(file, data: data)
        }
        guard case .sqlDump(let format) = file.kind else { throw PreviewError.unsupportedType }

        if format.contains("custom") {
            // pg_dump custom format: binary; the version follows the magic.
            var rows = [KeyValueRow("Format", "PostgreSQL custom-format dump")]
            if data.count > 7 {
                rows.append(KeyValueRow("Dump version", "\(data[5]).\(data[6]).\(data[7])"))
            }
            rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))
            rows.append(KeyValueRow("Note", "Restore with pg_restore; table listing planned"))
            return ArchiveMetadataRenderer.simple(file, "PostgreSQL Dump", "cylinder.split.1x2", rows)
        }

        // Plain SQL dump: count schema statements.
        let text = String(decoding: data, as: UTF8.self)
        let tables = Self.matches("CREATE TABLE[^(;]*", in: text)
        var rows = [
            KeyValueRow("Format", format),
            KeyValueRow("Tables created", "\(tables.count)"),
            KeyValueRow("INSERT statements", "\(text.components(separatedBy: "INSERT INTO").count - 1)"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if UInt64(data.count) < file.fileSize {
            rows.append(KeyValueRow("Note", "Counts from the first \(Format.bytes(UInt64(data.count)))"))
        }

        var sections: [PreviewSection] = [.keyValues(title: "Dump", rows: rows)]
        if !tables.isEmpty {
            let names = tables.prefix(50).map {
                $0.replacingOccurrences(of: "CREATE TABLE", with: "")
                    .replacingOccurrences(of: "IF NOT EXISTS", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " `\"\n"))
            }
            sections.append(.keyValues(title: "Tables", rows: names.map { KeyValueRow("", $0) }))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) Database Dump",
            iconSystemName: "cylinder.split.1x2",
            sections: sections
        )
    }

    private func renderTerraformState(_ file: DetectedFile, data: Data) throws -> PreviewDocument {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PreviewError.corruptFile("invalid Terraform state JSON")
        }
        var rows: [KeyValueRow] = []
        if let version = json["version"] { rows.append(KeyValueRow("State version", "\(version)")) }
        if let tfVersion = json["terraform_version"] as? String {
            rows.append(KeyValueRow("Terraform version", tfVersion))
        }
        if let serial = json["serial"] { rows.append(KeyValueRow("Serial", "\(serial)")) }

        var typeCounts: [String: Int] = [:]
        let resources = json["resources"] as? [[String: Any]] ?? []
        for resource in resources {
            let type = resource["type"] as? String ?? "?"
            typeCounts[type, default: 0] += 1
        }
        rows.append(KeyValueRow("Resources", "\(resources.count)"))
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        var sections: [PreviewSection] = [.keyValues(title: "Terraform State", rows: rows)]
        if !typeCounts.isEmpty {
            let typeRows = typeCounts.sorted { $0.value > $1.value }.prefix(40)
                .map { KeyValueRow($0.key, "\($0.value)") }
            sections.append(.keyValues(title: "Resource Types", rows: typeRows))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Terraform State",
            iconSystemName: "square.stack.3d.up",
            sections: sections
        )
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).prefix(500).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
