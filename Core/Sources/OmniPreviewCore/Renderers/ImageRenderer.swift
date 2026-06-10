import Foundation
import ImageIO

/// Image preview with dimensions, color info, EXIF camera data, and
/// AI-generation metadata (Automatic1111 / ComfyUI) for PNG files.
public struct ImageRenderer: PreviewRenderer {
    public static let id = "image"
    public static let displayName = "Image"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        if case .image = file.kind { return true }
        return false
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard case .image(let format) = file.kind else { throw PreviewError.unsupportedType }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, options) else {
            throw PreviewError.corruptFile("ImageIO could not parse this image")
        }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]) ?? [:]

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        var rows = [KeyValueRow("Format", format), KeyValueRow("File size", Format.bytes(file.fileSize))]
        if width > 0, height > 0 {
            rows.insert(KeyValueRow("Dimensions", "\(width) × \(height)"), at: 0)
        }
        if let colorModel = properties[kCGImagePropertyColorModel] as? String {
            var color = colorModel
            if let depth = properties[kCGImagePropertyDepth] as? Int { color += " \(depth)-bit" }
            if properties[kCGImagePropertyHasAlpha] as? Bool == true { color += " + alpha" }
            rows.append(KeyValueRow("Color", color))
        }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            rows.append(KeyValueRow("Resolution", "\(Int(dpi)) DPI"))
        }
        let frameCount = CGImageSourceGetCount(source)
        if frameCount > 1 {
            rows.append(KeyValueRow("Frames", "\(frameCount)"))
        }

        var sections: [PreviewSection] = [
            .image(file.url),
            .keyValues(title: "Image", rows: rows),
        ]

        let cameraRows = Self.cameraRows(properties)
        if !cameraRows.isEmpty {
            sections.append(.keyValues(title: "Camera", rows: cameraRows))
        }
        if format == "PNG" {
            sections.append(contentsOf: AIImageMetadata.sections(pngFileURL: file.url))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: width > 0 && height > 0
                ? "\(format) Image — \(width) × \(height)"
                : "\(format) Image",
            iconSystemName: "photo",
            sections: sections
        )
    }

    static func cameraRows(_ properties: [CFString: Any]) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        if make != nil || model != nil {
            rows.append(KeyValueRow("Camera", [make, model].compactMap { $0 }.joined(separator: " ")))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String {
            rows.append(KeyValueRow("Lens", lens))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
            rows.append(KeyValueRow("Focal length", "\(focal.formatted()) mm"))
        }
        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
            rows.append(KeyValueRow("Aperture", "ƒ/\(fNumber.formatted())"))
        }
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
            let text = exposure < 1 ? "1/\(Int((1 / exposure).rounded())) s" : "\(exposure.formatted()) s"
            rows.append(KeyValueRow("Exposure", text))
        }
        if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoValues.first {
            rows.append(KeyValueRow("ISO", "\(iso)"))
        }
        if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            rows.append(KeyValueRow("Taken", date))
        }
        return rows
    }
}
