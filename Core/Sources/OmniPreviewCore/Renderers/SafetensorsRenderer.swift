import Foundation

/// Safetensors layout: 8-byte little-endian header length, then a JSON header
/// mapping tensor names to dtype/shape/offsets. Only the header is read.
public struct SafetensorsRenderer: PreviewRenderer {
    public static let id = "safetensors"
    public static let displayName = "Safetensors Model"

    static let maxHeaderSize: UInt64 = 50 * 1024 * 1024
    static let maxListedTensors = 200

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .safetensors }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }

        guard let lengthData = try handle.read(upToCount: 8), lengthData.count == 8 else {
            throw PreviewError.corruptFile("missing header length")
        }
        var lengthReader = DataReader(lengthData)
        let headerLength = try lengthReader.readU64LE()
        guard headerLength <= Self.maxHeaderSize, headerLength + 8 <= file.fileSize else {
            throw PreviewError.corruptFile("implausible header length \(headerLength)")
        }

        guard let headerData = try handle.read(upToCount: Int(headerLength)),
              let json = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw PreviewError.corruptFile("header is not valid JSON")
        }

        var metadataRows: [KeyValueRow] = []
        if let metadata = json["__metadata__"] as? [String: Any] {
            for key in metadata.keys.sorted() {
                metadataRows.append(KeyValueRow(key, "\(metadata[key] ?? "")"))
            }
        }

        var tensorRows: [[String]] = []
        var totalParameters: UInt64 = 0
        var dtypeCounts: [String: Int] = [:]
        let tensorNames = json.keys.filter { $0 != "__metadata__" }.sorted()
        for name in tensorNames {
            guard let tensor = json[name] as? [String: Any] else { continue }
            let dtype = tensor["dtype"] as? String ?? "?"
            let shape = (tensor["shape"] as? [Int]) ?? []
            dtypeCounts[dtype, default: 0] += 1
            totalParameters += shape.reduce(UInt64(1)) { $0 * UInt64(max($1, 0)) }
            if tensorRows.count < Self.maxListedTensors {
                tensorRows.append([name, dtype, shape.map(String.init).joined(separator: " × ")])
            }
        }

        var summary = [
            KeyValueRow("Tensors", "\(tensorNames.count)"),
            KeyValueRow("Parameters", totalParameters.formatted()),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
            KeyValueRow("Data types", dtypeCounts.keys.sorted().map { "\($0) (\(dtypeCounts[$0]!))" }.joined(separator: ", ")),
        ]
        if tensorNames.count > Self.maxListedTensors {
            summary.append(KeyValueRow("Note", "Showing first \(Self.maxListedTensors) tensors"))
        }

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: summary)]
        if !metadataRows.isEmpty {
            sections.append(.keyValues(title: "Metadata", rows: metadataRows))
        }
        sections.append(.table(title: "Tensors", columns: ["Name", "Type", "Shape"], rows: tensorRows))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Safetensors Model",
            iconSystemName: "brain",
            sections: sections
        )
    }
}
