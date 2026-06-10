import Foundation

/// Header-only metadata for GPU/texture image formats that ImageIO cannot
/// decode: QOI, DDS, TGA, KTX, KTX2, Radiance HDR.
public struct TextureRenderer: PreviewRenderer {
    public static let id = "texture"
    public static let displayName = "Texture Images"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .texture = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .texture(let format) = file.kind else { throw PreviewError.unsupportedType }
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4096) ?? Data()
        var reader = DataReader(head)

        var rows: [KeyValueRow] = []
        switch format {
        case "QOI":
            try reader.skip(4)
            let width = try reader.readU32BE()
            let height = try reader.readU32BE()
            let channels = try reader.readU8()
            let colorspace = try reader.readU8()
            rows = [
                KeyValueRow("Dimensions", "\(width) × \(height)"),
                KeyValueRow("Channels", channels == 4 ? "RGBA" : "RGB"),
                KeyValueRow("Colorspace", colorspace == 0 ? "sRGB" : "Linear"),
            ]

        case "DDS":
            try reader.skip(4 + 4 + 4) // magic, header size, flags
            let height = try reader.readU32LE()
            let width = try reader.readU32LE()
            try reader.skip(4 + 4) // pitch, depth
            let mipCount = try reader.readU32LE()
            try reader.skip(11 * 4 + 4 + 4) // reserved, pixel format size/flags
            let fourCC = try reader.readString(4)
            rows = [
                KeyValueRow("Dimensions", "\(width) × \(height)"),
                KeyValueRow("Mip levels", "\(max(mipCount, 1))"),
                KeyValueRow("Compression", fourCC.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Uncompressed" : fourCC),
            ]

        case "TGA":
            try reader.skip(12)
            let width = try reader.readU16LE()
            let height = try reader.readU16LE()
            let depth = try reader.readU8()
            rows = [
                KeyValueRow("Dimensions", "\(width) × \(height)"),
                KeyValueRow("Bit depth", "\(depth)-bit"),
            ]

        case "KTX":
            try reader.skip(12 + 4 + 4 + 4 + 4 + 4 + 4) // identifier, endianness, GL types
            let internalFormat = try reader.readU32LE()
            try reader.skip(4)
            let width = try reader.readU32LE()
            let height = try reader.readU32LE()
            rows = [
                KeyValueRow("Dimensions", "\(width) × \(max(height, 1))"),
                KeyValueRow("GL internal format", String(format: "0x%04X", internalFormat)),
            ]

        case "KTX2":
            try reader.skip(12)
            let vkFormat = try reader.readU32LE()
            try reader.skip(4)
            let width = try reader.readU32LE()
            let height = try reader.readU32LE()
            try reader.skip(4 + 4 + 4)
            let levels = try reader.readU32LE()
            rows = [
                KeyValueRow("Dimensions", "\(width) × \(max(height, 1))"),
                KeyValueRow("Vulkan format", "\(vkFormat)"),
                KeyValueRow("Mip levels", "\(max(levels, 1))"),
            ]

        case "Radiance HDR":
            let text = String(decoding: head, as: UTF8.self)
            if let match = text.range(of: "-Y ") ?? text.range(of: "+Y ") {
                let line = text[match.lowerBound...].prefix(while: { $0 != "\n" })
                rows.append(KeyValueRow("Resolution line", String(line)))
            }
            rows.append(KeyValueRow("Format", "RGBE high dynamic range"))

        default:
            break
        }
        rows.append(KeyValueRow("File size", Format.bytes(file.fileSize)))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(format) Texture",
            iconSystemName: "photo.on.rectangle",
            sections: [.keyValues(title: "Texture", rows: rows)]
        )
    }
}
