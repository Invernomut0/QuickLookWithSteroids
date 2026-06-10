import Foundation

/// 3D model previews: geometry statistics for STL/OBJ/PLY/GLB/glTF, plus an
/// interactive SceneKit viewer (the UI layer renders the `model3D` section)
/// for the formats ModelIO can import (STL, OBJ, PLY, USDZ).
public struct ThreeDRenderer: PreviewRenderer {
    public static let id = "model3d"
    public static let displayName = "3D Models"

    static let viewerExtensions: Set<String> = ["stl", "obj", "ply", "usdz"]
    static let maxTextRead = 32 * 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .model3D = file.kind { return true }
        return file.kind == .zip && file.pathExtension == "usdz"
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let format: String
        if case .model3D(let f) = file.kind {
            format = f
        } else {
            format = "USDZ"
        }

        var rows: [KeyValueRow] = []
        switch format {
        case "STL": rows = try stlRows(file)
        case "OBJ": rows = try objRows(file)
        case "PLY": rows = try plyRows(file)
        case "GLB": rows = try glbRows(file)
        case "glTF": rows = try gltfRows(try Data(contentsOf: file.url, options: .alwaysMapped))
        case "USDZ":
            let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
            rows = [KeyValueRow("Package entries", "\(archive.entries.count)")]
        default: break
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        var sections: [PreviewSection] = []
        if Self.viewerExtensions.contains(file.pathExtension) {
            sections.append(.model3D(file.url))
        }
        sections.append(.keyValues(title: "\(format) Model", rows: rows))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) 3D Model",
            iconSystemName: "cube",
            sections: sections
        )
    }

    private func stlRows(_ file: DetectedFile) throws -> [KeyValueRow] {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 1024) ?? Data()

        // ASCII STL starts with "solid"; binary has a u32 triangle count at offset 80.
        if head.starts(with: Array("solid".utf8)),
           String(decoding: head, as: UTF8.self).contains("facet") {
            return [KeyValueRow("Encoding", "ASCII")]
        }
        guard head.count >= 84 else { throw PreviewError.corruptFile("truncated STL header") }
        var reader = DataReader(head)
        try reader.skip(80)
        let triangles = try reader.readU32LE()
        let expectedSize = 84 + UInt64(triangles) * 50
        var rows = [
            KeyValueRow("Encoding", "Binary"),
            KeyValueRow("Triangles", "\(triangles)"),
        ]
        if expectedSize != file.fileSize {
            rows.append(KeyValueRow("Note", "Size mismatch — header may be unreliable"))
        }
        return rows
    }

    private func objRows(_ file: DetectedFile) throws -> [KeyValueRow] {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxTextRead) ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        var vertices = 0, faces = 0, normals = 0, objects = 0
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("v ") { vertices += 1 }
            else if line.hasPrefix("f ") { faces += 1 }
            else if line.hasPrefix("vn ") { normals += 1 }
            else if line.hasPrefix("o ") || line.hasPrefix("g ") { objects += 1 }
        }
        var rows = [
            KeyValueRow("Vertices", "\(vertices)"),
            KeyValueRow("Faces", "\(faces)"),
        ]
        if normals > 0 { rows.append(KeyValueRow("Normals", "\(normals)")) }
        if objects > 0 { rows.append(KeyValueRow("Objects/groups", "\(objects)")) }
        if UInt64(data.count) < file.fileSize {
            rows.append(KeyValueRow("Note", "Counts from the first \(Format.bytes(UInt64(data.count)))"))
        }
        return rows
    }

    private func plyRows(_ file: DetectedFile) throws -> [KeyValueRow] {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
        let text = String(decoding: head, as: UTF8.self)

        var rows: [KeyValueRow] = []
        for line in text.components(separatedBy: "\n").prefix(100) {
            if line.hasPrefix("format ") {
                rows.append(KeyValueRow("Encoding", String(line.dropFirst(7))))
            } else if line.hasPrefix("element ") {
                let parts = line.split(separator: " ")
                if parts.count == 3 {
                    rows.append(KeyValueRow(String(parts[1]).capitalized, String(parts[2])))
                }
            } else if line.hasPrefix("end_header") {
                break
            }
        }
        return rows
    }

    private func glbRows(_ file: DetectedFile) throws -> [KeyValueRow] {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 16 * 1024 * 1024) ?? Data()
        var reader = DataReader(data)
        try reader.skip(4)
        let version = try reader.readU32LE()
        try reader.skip(4) // total length
        let jsonLength = try reader.readU32LE()
        let chunkType = try reader.readString(4)
        guard chunkType == "JSON", jsonLength <= UInt32(reader.remaining) else {
            throw PreviewError.corruptFile("missing GLB JSON chunk")
        }
        let json = Data(try reader.read(Int(jsonLength)))
        var rows = try gltfRows(json)
        rows.insert(KeyValueRow("GLB version", "\(version)"), at: 0)
        return rows
    }

    private func gltfRows(_ jsonData: Data) throws -> [KeyValueRow] {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw PreviewError.corruptFile("invalid glTF JSON")
        }
        var rows: [KeyValueRow] = []
        if let asset = json["asset"] as? [String: Any] {
            if let generator = asset["generator"] as? String { rows.append(KeyValueRow("Generator", generator)) }
            if let version = asset["version"] as? String { rows.append(KeyValueRow("glTF version", version)) }
        }
        let counts: [(String, String)] = [
            ("meshes", "Meshes"), ("nodes", "Nodes"), ("materials", "Materials"),
            ("animations", "Animations"), ("textures", "Textures"), ("skins", "Skins"),
        ]
        for (key, label) in counts {
            if let array = json[key] as? [Any], !array.isEmpty {
                rows.append(KeyValueRow(label, "\(array.count)"))
            }
        }
        return rows
    }
}
