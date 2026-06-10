import Foundation

/// NumPy .npy array preview: dtype, shape, element count from the header —
/// array data itself is never loaded.
public struct NPYRenderer: PreviewRenderer {
    public static let id = "npy"
    public static let displayName = "NumPy Array"

    static let maxHeaderLength = 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .npy }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        var reader = DataReader(try handle.read(upToCount: 64 * 1024) ?? Data())

        guard try reader.read(6) == [0x93] + Array("NUMPY".utf8) else {
            throw PreviewError.corruptFile("bad NPY magic")
        }
        let major = try reader.readU8()
        try reader.skip(1) // minor version
        let headerLength: Int
        if major == 1 {
            headerLength = Int(try reader.readU16LE())
        } else {
            headerLength = Int(try reader.readU32LE())
        }
        guard headerLength <= Self.maxHeaderLength else {
            throw PreviewError.corruptFile("implausible header length \(headerLength)")
        }
        let header = try reader.readString(min(headerLength, reader.remaining))

        // Header is a Python dict literal, e.g.
        // {'descr': '<f4', 'fortran_order': False, 'shape': (3, 4), }
        let descr = Self.match(header, pattern: "'descr':\\s*'([^']+)'") ?? "?"
        let fortran = Self.match(header, pattern: "'fortran_order':\\s*(True|False)") ?? "False"
        let shapeText = Self.match(header, pattern: "'shape':\\s*\\(([^)]*)\\)") ?? ""
        let shape = shapeText.split(separator: ",")
            .compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        let elements = shape.isEmpty ? 1 : shape.reduce(UInt64(1)) { $0 &* $1 }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "NumPy Array",
            iconSystemName: "square.grid.3x3",
            sections: [
                .keyValues(title: "Array", rows: [
                    KeyValueRow("Data type", Self.dtypeDescription(descr)),
                    KeyValueRow("Shape", shape.isEmpty ? "scalar" : shape.map(String.init).joined(separator: " × ")),
                    KeyValueRow("Elements", elements.formatted()),
                    KeyValueRow("Order", fortran == "True" ? "Fortran (column-major)" : "C (row-major)"),
                    KeyValueRow("File size", Format.bytes(file.fileSize)),
                    KeyValueRow("Format version", "\(major).x"),
                ]),
            ]
        )
    }

    private static func match(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func dtypeDescription(_ descr: String) -> String {
        let names: [String: String] = [
            "f2": "float16", "f4": "float32", "f8": "float64",
            "i1": "int8", "i2": "int16", "i4": "int32", "i8": "int64",
            "u1": "uint8", "u2": "uint16", "u4": "uint32", "u8": "uint64",
            "b1": "bool", "c8": "complex64", "c16": "complex128",
        ]
        let stripped = descr.trimmingCharacters(in: CharacterSet(charactersIn: "<>=|"))
        if let name = names[stripped] {
            return "\(name) (\(descr))"
        }
        return descr
    }
}
