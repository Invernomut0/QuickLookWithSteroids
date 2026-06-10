import Foundation

/// Scientific / columnar data formats: header-level metadata for Parquet,
/// Arrow, DuckDB, HDF5; structural metadata for NetCDF, MATLAB, FITS.
public struct DataFileRenderer: PreviewRenderer {
    public static let id = "data-file"
    public static let displayName = "Scientific Data"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .dataFile = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .dataFile(let format) = file.kind else { throw PreviewError.unsupportedType }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()

        var rows: [KeyValueRow] = []
        switch format {
        case "Parquet":
            // Footer: 4-byte metadata length + "PAR1" at the very end.
            if file.fileSize >= 12 {
                try handle.seek(toOffset: file.fileSize - 8)
                var tail = DataReader(try handle.read(upToCount: 8) ?? Data())
                let metadataLength = try tail.readU32LE()
                let magic = try tail.readString(4)
                if magic == "PAR1" {
                    rows.append(KeyValueRow("Footer metadata", Format.bytes(UInt64(metadataLength))))
                }
            }
            rows.append(KeyValueRow("Note", "Schema decoding (Thrift) planned"))

        case "Arrow":
            rows.append(KeyValueRow("Container", "Arrow IPC file"))

        case "DuckDB":
            var reader = DataReader(head)
            try reader.skip(12)
            let version = try reader.readU64LE()
            rows.append(KeyValueRow("Storage version", "\(version)"))

        case "HDF5":
            if head.count > 8 {
                rows.append(KeyValueRow("Superblock version", "\(head[8])"))
            }

        case "NetCDF":
            rows.append(contentsOf: Self.netCDFRows(head))

        case "MATLAB":
            // v5 header: 116 bytes of description text.
            let description = String(decoding: head.prefix(116), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty { rows.append(KeyValueRow("Header", description)) }
            if head.count >= 126 {
                let versionField = UInt16(head[124]) | UInt16(head[125]) << 8
                rows.append(KeyValueRow("MAT version", versionField == 0x0100 ? "5" : String(format: "0x%04X", versionField)))
            }

        case "FITS":
            rows.append(contentsOf: Self.fitsRows(head))

        default:
            break
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) Data File",
            iconSystemName: "chart.bar.doc.horizontal",
            sections: [.keyValues(title: format, rows: rows)]
        )
    }

    /// NetCDF classic header: magic, numrecs, then the dimension list.
    static func netCDFRows(_ head: Data) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        var reader = DataReader(head)
        guard (try? reader.skip(3)) != nil, let version = try? reader.readU8() else { return rows }
        rows.append(KeyValueRow("Format", version == 2 ? "Classic (64-bit offsets)" : "Classic"))
        guard let _ = try? reader.readU32BE(), // numrecs
              let tag = try? reader.readU32BE(), tag == 0x0A, // NC_DIMENSION
              let count = try? reader.readU32BE(), count <= 256 else { return rows }
        var dims: [String] = []
        for _ in 0..<count {
            guard let nameLength = try? reader.readU32BE(), nameLength <= 1024,
                  let name = try? reader.readString(Int(nameLength)) else { break }
            let padding = (4 - Int(nameLength) % 4) % 4
            guard (try? reader.skip(padding)) != nil,
                  let size = try? reader.readU32BE() else { break }
            dims.append("\(name)=\(size == 0 ? "unlimited" : String(size))")
        }
        if !dims.isEmpty {
            rows.append(KeyValueRow("Dimensions", dims.joined(separator: ", ")))
        }
        return rows
    }

    /// FITS primary header: 80-character cards up to END.
    static func fitsRows(_ head: Data) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        let interesting = ["BITPIX", "NAXIS", "NAXIS1", "NAXIS2", "NAXIS3", "TELESCOP", "INSTRUME", "OBJECT", "DATE-OBS"]
        var offset = 0
        while offset + 80 <= head.count, offset < 32 * 1024 {
            let card = String(decoding: head[offset..<offset + 80], as: UTF8.self)
            offset += 80
            if card.hasPrefix("END") { break }
            let keyword = String(card.prefix(8)).trimmingCharacters(in: .whitespaces)
            guard interesting.contains(keyword), let equals = card.firstIndex(of: "=") else { continue }
            var value = String(card[card.index(after: equals)...])
            if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " '"))
            rows.append(KeyValueRow(keyword, value))
        }
        return rows
    }
}

/// ONNX models are protobuf; a minimal field walk extracts the producer and
/// IR version without a protobuf library.
public struct ONNXRenderer: PreviewRenderer {
    public static let id = "onnx"
    public static let displayName = "ONNX Model"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .onnx }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 1024 * 1024) ?? Data()

        var rows: [KeyValueRow] = []
        var reader = DataReader(head)
        // Walk top-level ModelProto fields: 1=ir_version, 2=producer_name,
        // 3=producer_version, 8=model_version; stop at the graph (field 7).
        for _ in 0..<32 {
            guard let tag = try? Self.varint(&reader) else { break }
            let field = tag >> 3
            let wire = tag & 0x7
            if field == 7 { break }
            switch (field, wire) {
            case (1, 0):
                if let v = try? Self.varint(&reader) { rows.append(KeyValueRow("IR version", "\(v)")) }
            case (8, 0):
                if let v = try? Self.varint(&reader) { rows.append(KeyValueRow("Model version", "\(v)")) }
            case (2, 2), (3, 2), (4, 2):
                guard let length = try? Self.varint(&reader), length <= 4096,
                      let text = try? reader.readString(Int(length)) else { break }
                let label = field == 2 ? "Producer" : field == 3 ? "Producer version" : "Domain"
                if !text.isEmpty { rows.append(KeyValueRow(label, text)) }
            case (_, 0):
                _ = try? Self.varint(&reader)
            case (_, 2):
                guard let length = try? Self.varint(&reader),
                      (try? reader.skip(Int(min(length, UInt64(reader.remaining))))) != nil else { break }
            default:
                break
            }
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "ONNX Model",
            iconSystemName: "brain",
            sections: [.keyValues(title: "Model", rows: rows)]
        )
    }

    static func varint(_ reader: inout DataReader) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            let byte = try reader.readU8()
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw PreviewError.corruptFile("varint too long")
    }
}
