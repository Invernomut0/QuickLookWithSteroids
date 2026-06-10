import Foundation

/// NumPy .npy array preview: dtype, shape, element count from the header —
/// array data itself is never loaded.
public struct NPYRenderer: PreviewRenderer {
    public static let id = "npy"
    public static let displayName = "NumPy Array"

    static let maxHeaderLength = 1024 * 1024

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .npy }

    struct HeaderInfo {
        let descr: String
        let fortran: Bool
        let shapeDims: [UInt64]
        var dtype: String { NPYRenderer.dtypeDescription(descr) }
        var shape: String {
            shapeDims.isEmpty ? "scalar" : shapeDims.map(String.init).joined(separator: " × ")
        }
        var elements: UInt64 {
            shapeDims.isEmpty ? 1 : shapeDims.reduce(UInt64(1)) { $0 &* $1 }
        }
    }

    /// Parses an NPY header from a (possibly partial) data prefix.
    /// The header is a Python dict literal, e.g.
    /// {'descr': '<f4', 'fortran_order': False, 'shape': (3, 4), }
    static func headerInfo(from data: Data) -> HeaderInfo? {
        var reader = DataReader(data)
        guard let magic = try? reader.read(6), magic == [0x93] + Array("NUMPY".utf8),
              let major = try? reader.readU8(), (try? reader.skip(1)) != nil else { return nil }
        let headerLength: Int
        if major == 1 {
            guard let length = try? reader.readU16LE() else { return nil }
            headerLength = Int(length)
        } else {
            guard let length = try? reader.readU32LE() else { return nil }
            headerLength = Int(length)
        }
        guard headerLength <= maxHeaderLength,
              let header = try? reader.readString(min(headerLength, reader.remaining)) else { return nil }

        let descr = match(header, pattern: "'descr':\\s*'([^']+)'") ?? "?"
        let fortran = match(header, pattern: "'fortran_order':\\s*(True|False)") == "True"
        let shapeText = match(header, pattern: "'shape':\\s*\\(([^)]*)\\)") ?? ""
        let shape = shapeText.split(separator: ",")
            .compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        return HeaderInfo(descr: descr, fortran: fortran, shapeDims: shape)
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()

        guard let info = Self.headerInfo(from: head) else {
            throw PreviewError.corruptFile("invalid NPY header")
        }
        var versionReader = DataReader(head)
        try versionReader.skip(6)
        let major = try versionReader.readU8()

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "NumPy Array",
            iconSystemName: "square.grid.3x3",
            sections: [
                .keyValues(title: "Array", rows: [
                    KeyValueRow("Data type", info.dtype),
                    KeyValueRow("Shape", info.shape),
                    KeyValueRow("Elements", info.elements.formatted()),
                    KeyValueRow("Order", info.fortran ? "Fortran (column-major)" : "C (row-major)"),
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
