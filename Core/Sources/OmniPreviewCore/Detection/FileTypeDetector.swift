import Foundation

public enum FileTypeDetector {

    /// Enough to cover every signature we check: tar needs offset 257,
    /// ISO 9660 needs the volume descriptor at offset 32769.
    static let headReadSize = 33 * 1024

    /// Extensions mapped to source-code language names, used as a fallback
    /// when no binary signature matches.
    static let sourceLanguages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++",
        "py": "Python", "go": "Go", "rs": "Rust",
        "c": "C", "h": "C/C++ Header", "cpp": "C++", "cc": "C++", "hpp": "C++ Header",
        "cs": "C#", "java": "Java", "kt": "Kotlin",
        "js": "JavaScript", "jsx": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript",
        "php": "PHP", "rb": "Ruby", "lua": "Lua",
        "sh": "Shell", "bash": "Shell", "zsh": "Shell",
        "sql": "SQL", "html": "HTML", "css": "CSS",
        "xml": "XML", "yaml": "YAML", "yml": "YAML",
        "json": "JSON", "toml": "TOML", "ini": "INI",
        "dockerfile": "Dockerfile", "tf": "Terraform", "nix": "Nix",
    ]

    /// TIFF-based camera RAW formats distinguished by extension once the
    /// TIFF signature matched.
    static let tiffRawFormats: [String: String] = [
        "cr2": "Canon CR2 RAW", "nef": "Nikon NEF RAW", "arw": "Sony ARW RAW",
        "orf": "Olympus ORF RAW", "rw2": "Panasonic RW2 RAW", "pef": "Pentax PEF RAW",
        "dng": "DNG RAW",
    ]

    public static func detect(url: URL) throws -> DetectedFile {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if (attributes[.type] as? FileAttributeType) == .typeDirectory {
            return DetectedFile(url: url, kind: .folder, fileSize: 0)
        }
        let fileSize = (attributes[.size] as? UInt64) ?? 0

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: headReadSize) ?? Data()

        let kind = detectKind(head: head, url: url)
        return DetectedFile(url: url, kind: kind, fileSize: fileSize)
    }

    static func detectKind(head: Data, url: URL) -> FileKind {
        let bytes = [UInt8](head.prefix(512))
        let ext = url.pathExtension.lowercased()

        func starts(_ signature: [UInt8]) -> Bool { bytes.starts(with: signature) }
        func starts(_ text: String) -> Bool { bytes.starts(with: Array(text.utf8)) }
        func at(_ offset: Int, _ text: String) -> Bool {
            let signature = Array(text.utf8)
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset..<offset + signature.count]) == signature
        }

        // MARK: Archives
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if starts([0x1F, 0x8B]) { return .gzip }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        if starts("BZh") { return .bzip2 }
        if starts("MSCF") { return .cab }
        if starts("!<arch>\n") { return .arArchive }
        if starts([0xED, 0xAB, 0xEE, 0xDB]) { return .rpmPackage }
        if starts("xar!") { return .xar }
        if starts([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return .compoundFile }
        if bytes.count >= 262, at(257, "ustar") { return .tar }
        // ISO 9660: primary volume descriptor at sector 16.
        if head.count > 32774, Array(head[32769..<32774]) == Array("CD001".utf8) { return .iso }
        if ext == "dmg" { return .dmg } // verified against the trailing koly block by the renderer

        // MARK: Databases & data
        if starts("SQLite format 3\0") { return .sqlite }
        if starts("PAR1") { return .dataFile(format: "Parquet") }
        if starts("ARROW1") { return .dataFile(format: "Arrow") }
        if at(8, "DUCK") { return .dataFile(format: "DuckDB") }
        if starts([0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]) { return .dataFile(format: "HDF5") }
        if starts("CDF\u{01}") || starts("CDF\u{02}") { return .dataFile(format: "NetCDF") }
        if starts("MATLAB") { return .dataFile(format: "MATLAB") }
        if starts("SIMPLE  =") { return .dataFile(format: "FITS") }
        if starts("PGDMP") { return .sqlDump(format: "PostgreSQL (custom format)") }
        if ext == "torrent", bytes.first == UInt8(ascii: "d") { return .torrent }
        if ext == "tfstate" { return .terraformState }

        // MARK: Machine learning
        if starts("GGUF") { return .gguf }
        if bytes.count >= 6, bytes[0] == 0x93, at(1, "NUMPY") { return .npy }
        if ext == "safetensors", bytes.count >= 9, bytes[8] == UInt8(ascii: "{") { return .safetensors }
        if ext == "onnx" { return .onnx }

        // MARK: Images & textures
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .image(format: "PNG") }
        if starts([0xFF, 0xD8, 0xFF]) { return .image(format: "JPEG") }
        if starts("GIF8") { return .image(format: "GIF") }
        if starts("8BPS") { return .image(format: bytes.count > 5 && bytes[5] == 2 ? "PSB" : "PSD") }
        if starts("icns") { return .image(format: "ICNS") }
        if starts([0x00, 0x00, 0x01, 0x00]), ["ico", "cur"].contains(ext) { return .image(format: "ICO") }
        if starts([0x76, 0x2F, 0x31, 0x01]) { return .image(format: "EXR") }
        if starts([0xFF, 0x0A]) || starts([0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20]) {
            return .image(format: "JPEG XL")
        }
        if starts("FUJIFILMCCD-RAW") { return .image(format: "Fuji RAF RAW") }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) {
            return .image(format: tiffRawFormats[ext] ?? "TIFF")
        }
        if starts("qoif") { return .texture(format: "QOI") }
        if starts("DDS ") { return .texture(format: "DDS") }
        if starts([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB]) { return .texture(format: "KTX") }
        if starts([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB]) { return .texture(format: "KTX2") }
        if starts("#?RADIANCE") || starts("#?RGBE") { return .texture(format: "Radiance HDR") }
        if ext == "tga", bytes.count >= 3, bytes[1] <= 1, [1, 2, 3, 9, 10, 11].contains(bytes[2]) {
            return .texture(format: "TGA")
        }

        // MARK: Audio / video
        if starts("fLaC") { return .audio(format: "FLAC") }
        if starts("OggS") { return .audio(format: "Ogg") }
        if starts("ID3") || (ext == "mp3" && bytes.first == 0xFF) { return .audio(format: "MP3") }
        if starts([0x1A, 0x45, 0xDF, 0xA3]) { return .video(format: ext == "webm" ? "WebM" : "Matroska") }
        if starts("RIFF"), bytes.count >= 12 {
            switch String(decoding: bytes[8..<12], as: UTF8.self) {
            case "WAVE": return .audio(format: "WAV")
            case "AVI ": return .video(format: "AVI")
            case "WEBP": return .image(format: "WebP")
            default: break
            }
        }
        if bytes.count >= 12, at(4, "ftyp") {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "mif1", "msf1": return .image(format: "HEIC")
            case "avif", "avis": return .image(format: "AVIF")
            case "crx ": return .image(format: "Canon CR3 RAW")
            case "M4A ": return .audio(format: "M4A")
            case "qt  ": return .video(format: "QuickTime")
            default: return .video(format: "MP4")
            }
        }

        // MARK: Documents & eBooks
        if starts("%PDF") { return .pdf }
        if bytes.count > 68, at(60, "BOOKMOBI") || at(60, "TEXtREAd") { return .mobi }
        if ext == "fb2" { return .fb2 }

        // MARK: 3D & CAD
        if starts("glTF") { return .model3D(format: "GLB") }
        if starts("ply") { return .model3D(format: "PLY") }
        if ext == "stl" { return .model3D(format: "STL") }
        if ext == "obj" { return .model3D(format: "OBJ") }
        if ext == "gltf" { return .model3D(format: "glTF") }
        if starts("ISO-10303-21") { return .cad(format: "STEP") }
        if starts("AC10") { return .cad(format: "DWG") }
        if ext == "dxf" { return .cad(format: "DXF") }
        if ["iges", "igs"].contains(ext) { return .cad(format: "IGES") }

        // MARK: VM disk images
        if starts([0x51, 0x46, 0x49, 0xFB]) { return .diskImage(format: "QCOW2") }
        if starts("KDMV") { return .diskImage(format: "VMDK") }
        if starts("vhdxfile") { return .diskImage(format: "VHDX") }

        // MARK: GIS
        if starts([0x00, 0x00, 0x27, 0x0A]) { return .geo(format: "Shapefile") }
        if ext == "geojson" { return .geo(format: "GeoJSON") }
        if ext == "kml" { return .geo(format: "KML") }

        // MARK: Fonts
        if starts([0x00, 0x01, 0x00, 0x00]) || starts("OTTO") || starts("ttcf")
            || starts("wOFF") || starts("wOF2") {
            return .font
        }

        // MARK: Security
        if starts("-----BEGIN ") { return .pemCertificate }
        if ["p12", "pfx"].contains(ext), bytes.first == 0x30 { return .pkcs12 }
        if ["der", "cer", "crt"].contains(ext), bytes.first == 0x30 { return .derCertificate }

        // MARK: Text-based fallbacks
        if ext == "sql" || ext == "dump" {
            let headText = String(decoding: head.prefix(4096), as: UTF8.self)
            if headText.contains("PostgreSQL database dump") { return .sqlDump(format: "PostgreSQL") }
            if headText.contains("MySQL dump") || headText.contains("MariaDB dump") {
                return .sqlDump(format: "MySQL")
            }
        }
        if url.lastPathComponent.lowercased() == "dockerfile" {
            return .sourceCode(language: "Dockerfile")
        }
        if let language = sourceLanguages[ext] {
            return .sourceCode(language: language)
        }
        return .unknown
    }
}
