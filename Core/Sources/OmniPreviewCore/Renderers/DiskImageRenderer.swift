import Foundation

/// Virtual machine disk images: QCOW2, VMDK (sparse), VHDX — header metadata
/// including virtual capacity where the header carries it.
public struct DiskImageRenderer: PreviewRenderer {
    public static let id = "disk-image"
    public static let displayName = "VM Disk Images"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .diskImage = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .diskImage(let format) = file.kind else { throw PreviewError.unsupportedType }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4096) ?? Data()
        var reader = DataReader(head)

        var rows: [KeyValueRow] = []
        switch format {
        case "QCOW2":
            try reader.skip(4)
            let version = try reader.readU32BE()
            try reader.skip(8 + 4) // backing file offset/size... (offset u64, size u32)
            try reader.skip(4)     // cluster bits
            let high = try reader.readU32BE()
            let low = try reader.readU32BE()
            let virtualSize = UInt64(high) << 32 | UInt64(low)
            rows = [
                KeyValueRow("Virtual size", Format.bytes(virtualSize)),
                KeyValueRow("QCOW version", "\(version)"),
            ]

        case "VMDK":
            try reader.skip(4)
            let version = try reader.readU32LE()
            try reader.skip(4) // flags
            let capacitySectors = try reader.readU64LE()
            rows = [
                KeyValueRow("Virtual size", Format.bytes(capacitySectors * 512)),
                KeyValueRow("VMDK version", "\(version)"),
                KeyValueRow("Layout", "Sparse extent"),
            ]

        case "VHDX":
            try reader.skip(8)
            let creatorBytes = try reader.read(512)
            let creator = String(bytes: creatorBytes, encoding: .utf16LittleEndian)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            if let creator, !creator.isEmpty {
                rows.append(KeyValueRow("Created by", creator))
            }

        default:
            break
        }
        rows.append(KeyValueRow("Image file size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) Disk Image",
            iconSystemName: "externaldrive",
            sections: [.keyValues(title: "Disk Image", rows: rows)]
        )
    }
}

/// CAD formats: DXF entity statistics, STEP/IGES header fields, DWG version.
public struct CADRenderer: PreviewRenderer {
    public static let id = "cad"
    public static let displayName = "CAD Drawings"

    static let maxTextRead = 8 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .cad = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .cad(let format) = file.kind else { throw PreviewError.unsupportedType }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxTextRead) ?? Data()

        var rows: [KeyValueRow] = []
        switch format {
        case "DXF":
            let text = String(decoding: data, as: UTF8.self)
            if let versionRange = text.range(of: "$ACADVER") {
                let after = text[versionRange.upperBound...].prefix(40)
                if let code = after.range(of: "AC10") {
                    let version = after[code.lowerBound...].prefix(6)
                    rows.append(KeyValueRow("AutoCAD version", Self.dwgVersionName(String(version))))
                }
            }
            // Entities appear as "0\n<NAME>" pairs inside the ENTITIES section.
            if let entitiesRange = text.range(of: "ENTITIES") {
                let section = text[entitiesRange.upperBound...]
                var counts: [String: Int] = [:]
                let entityNames = ["LINE", "CIRCLE", "ARC", "LWPOLYLINE", "POLYLINE", "TEXT", "MTEXT", "INSERT", "DIMENSION", "HATCH", "SPLINE"]
                for name in entityNames {
                    let count = section.components(separatedBy: "\n" + name + "\n").count - 1
                    if count > 0 { counts[name] = count }
                }
                for (name, count) in counts.sorted(by: { $0.value > $1.value }) {
                    rows.append(KeyValueRow(name.capitalized, "\(count)"))
                }
            }

        case "STEP":
            let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
            if let name = Self.firstQuoted(after: "FILE_NAME", in: text) {
                rows.append(KeyValueRow("Model name", name))
            }
            if let schema = Self.firstQuoted(after: "FILE_SCHEMA", in: text) {
                rows.append(KeyValueRow("Schema", schema))
            }
            let entityCount = String(decoding: data, as: UTF8.self)
                .components(separatedBy: "\n#").count - 1
            if entityCount > 0 { rows.append(KeyValueRow("Entities", "\(entityCount)")) }

        case "IGES":
            // Column 73 of each line carries the section letter; T-section
            // last line summarizes counts.
            let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
            let lines = text.components(separatedBy: "\n")
            let directoryLines = lines.filter { $0.count >= 73 && $0[$0.index($0.startIndex, offsetBy: 72)] == "D" }.count
            rows.append(KeyValueRow("Directory entries", "\(directoryLines)"))
            rows.append(KeyValueRow("Entities (approx.)", "\(directoryLines / 2)"))

        case "DWG":
            let version = String(decoding: data.prefix(6), as: UTF8.self)
            rows.append(KeyValueRow("Format version", Self.dwgVersionName(version)))
            rows.append(KeyValueRow("Note", "DWG is proprietary; geometry preview planned"))

        default:
            break
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) Drawing",
            iconSystemName: "compass.drawing",
            sections: [.keyValues(title: format, rows: rows)]
        )
    }

    static func firstQuoted(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let after = text[markerRange.upperBound...].prefix(512)
        guard let open = after.firstIndex(of: "'") else { return nil }
        let rest = after[after.index(after: open)...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        let value = String(rest[..<close])
        return value.isEmpty ? nil : value
    }

    static func dwgVersionName(_ code: String) -> String {
        let names: [String: String] = [
            "AC1014": "AutoCAD R14", "AC1015": "AutoCAD 2000", "AC1018": "AutoCAD 2004",
            "AC1021": "AutoCAD 2007", "AC1024": "AutoCAD 2010", "AC1027": "AutoCAD 2013",
            "AC1032": "AutoCAD 2018",
        ]
        return names[code] ?? code
    }
}
