import Foundation

/// Parses the GGUF header (version, tensor count, metadata key-values).
/// Only a bounded prefix of the file is read; tensor data is never touched.
public struct GGUFRenderer: PreviewRenderer {
    public static let id = "gguf"
    public static let displayName = "GGUF Model"

    static let maxHeaderRead = 16 * 1024 * 1024
    static let maxMetadataEntries = 1024
    static let maxStringLength = 1024 * 1024
    static let maxDisplayedArrayElements = 8

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .gguf }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxHeaderRead) ?? Data()
        var reader = DataReader(data)

        guard try reader.readString(4) == "GGUF" else {
            throw PreviewError.corruptFile("bad magic")
        }
        let version = try reader.readU32LE()
        guard (1...3).contains(version) else {
            throw PreviewError.corruptFile("unsupported GGUF version \(version)")
        }
        let tensorCount = try reader.readU64LE()
        let kvCount = try reader.readU64LE()
        guard kvCount <= Self.maxMetadataEntries else {
            throw PreviewError.corruptFile("implausible metadata count \(kvCount)")
        }

        var metadataRows: [KeyValueRow] = []
        var truncated = false
        for _ in 0..<kvCount {
            do {
                let key = try readGGUFString(&reader)
                let value = try readValue(&reader)
                metadataRows.append(KeyValueRow(key, value))
            } catch {
                // Header larger than our read window (e.g. a huge tokenizer
                // vocabulary): show what we have rather than failing.
                truncated = true
                break
            }
        }

        var summary = [
            KeyValueRow("GGUF version", "\(version)"),
            KeyValueRow("Tensors", "\(tensorCount)"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if let architecture = metadataRows.first(where: { $0.key == "general.architecture" }) {
            summary.insert(KeyValueRow("Architecture", architecture.value), at: 0)
        }
        if truncated {
            summary.append(KeyValueRow("Note", "Metadata partially shown (large header)"))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "GGUF Model",
            iconSystemName: "cpu",
            sections: [
                .keyValues(title: "Summary", rows: summary),
                .keyValues(title: "Metadata", rows: metadataRows),
            ]
        )
    }

    private func readGGUFString(_ reader: inout DataReader) throws -> String {
        let length = try reader.readU64LE()
        guard length <= UInt64(Self.maxStringLength) else {
            throw PreviewError.corruptFile("implausible string length \(length)")
        }
        return try reader.readString(Int(length))
    }

    /// GGUF metadata value type ids per the spec.
    private enum ValueType: UInt32 {
        case uint8 = 0, int8 = 1, uint16 = 2, int16 = 3
        case uint32 = 4, int32 = 5, float32 = 6, bool = 7
        case string = 8, array = 9, uint64 = 10, int64 = 11, float64 = 12

        var fixedSize: Int? {
            switch self {
            case .uint8, .int8, .bool: return 1
            case .uint16, .int16: return 2
            case .uint32, .int32, .float32: return 4
            case .uint64, .int64, .float64: return 8
            case .string, .array: return nil
            }
        }
    }

    private func readValue(_ reader: inout DataReader) throws -> String {
        let rawType = try reader.readU32LE()
        guard let type = ValueType(rawValue: rawType) else {
            throw PreviewError.corruptFile("unknown metadata type \(rawType)")
        }
        return try readValue(of: type, &reader)
    }

    private func readValue(of type: ValueType, _ reader: inout DataReader) throws -> String {
        switch type {
        case .uint8: return "\(try reader.readU8())"
        case .int8: return "\(Int8(bitPattern: try reader.readU8()))"
        case .uint16: return "\(try reader.readU16LE())"
        case .int16: return "\(Int16(bitPattern: try reader.readU16LE()))"
        case .uint32: return "\(try reader.readU32LE())"
        case .int32: return "\(Int32(bitPattern: try reader.readU32LE()))"
        case .uint64: return "\(try reader.readU64LE())"
        case .int64: return "\(Int64(bitPattern: try reader.readU64LE()))"
        case .float32: return "\(Float(bitPattern: try reader.readU32LE()))"
        case .float64: return "\(Double(bitPattern: try reader.readU64LE()))"
        case .bool: return try reader.readU8() != 0 ? "true" : "false"
        case .string: return try readGGUFString(&reader)
        case .array:
            let rawElementType = try reader.readU32LE()
            guard let elementType = ValueType(rawValue: rawElementType) else {
                throw PreviewError.corruptFile("unknown array element type \(rawElementType)")
            }
            let rawCount = try reader.readU64LE()
            // A hostile count must throw, never trap on Int conversion or
            // overflow in the skip computation below.
            guard let count = Int(exactly: rawCount) else {
                throw PreviewError.corruptFile("implausible array count \(rawCount)")
            }
            var shown: [String] = []
            if let size = elementType.fixedSize {
                let (totalBytes, overflow) = count.multipliedReportingOverflow(by: size)
                guard !overflow, totalBytes <= reader.remaining else {
                    throw PreviewError.corruptFile("array of \(count) elements extends past end of data")
                }
                // Fixed-size elements: render a few, then skip the rest cheaply.
                let displayCount = min(count, Self.maxDisplayedArrayElements)
                for _ in 0..<displayCount {
                    shown.append(try readValue(of: elementType, &reader))
                }
                try reader.skip((count - displayCount) * size)
            } else {
                // Variable-size elements (strings) must be walked one by one;
                // tokenizer vocabularies can exceed the read window, in which
                // case the thrown error truncates metadata gracefully upstream.
                for index in 0..<count {
                    let value = try readValue(of: elementType, &reader)
                    if index < Self.maxDisplayedArrayElements { shown.append(value) }
                }
            }
            let suffix = count > Self.maxDisplayedArrayElements ? ", … \(count) items" : ""
            return "[" + shown.joined(separator: ", ") + suffix + "]"
        }
    }
}
