import Foundation

public enum FileTypeDetector {

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

    public static func detect(url: URL) throws -> DetectedFile {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? UInt64) ?? 0

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // 512 bytes covers every signature we check; tar needs offset 257.
        let head = try handle.read(upToCount: 512) ?? Data()

        let kind = detectKind(head: head, url: url)
        return DetectedFile(url: url, kind: kind, fileSize: fileSize)
    }

    static func detectKind(head: Data, url: URL) -> FileKind {
        let bytes = [UInt8](head)
        let ext = url.pathExtension.lowercased()

        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return .zip
        }
        if bytes.starts(with: [0x1F, 0x8B]) { return .gzip }
        if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if bytes.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) { return .rar }
        if bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        if bytes.starts(with: Array("SQLite format 3\0".utf8)) { return .sqlite }
        if bytes.starts(with: Array("GGUF".utf8)) { return .gguf }
        if bytes.starts(with: Array("%PDF".utf8)) { return .pdf }
        if bytes.count >= 262, Array(bytes[257..<262]) == Array("ustar".utf8) { return .tar }

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .image(format: "PNG") }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .image(format: "JPEG") }
        if bytes.starts(with: Array("GIF8".utf8)) { return .image(format: "GIF") }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return .image(format: "TIFF")
        }
        if bytes.starts(with: [0x93]) && bytes.count >= 6 && Array(bytes[1..<6]) == Array("NUMPY".utf8) {
            return .npy
        }
        if bytes.starts(with: Array("fLaC".utf8)) { return .audio(format: "FLAC") }
        if bytes.starts(with: Array("OggS".utf8)) { return .audio(format: "Ogg") }
        if bytes.starts(with: Array("ID3".utf8)) || (ext == "mp3" && bytes.first == 0xFF) {
            return .audio(format: "MP3")
        }

        // RIFF containers: WAV, AVI, WebP share the same outer signature.
        if bytes.starts(with: Array("RIFF".utf8)), bytes.count >= 12 {
            let riffType = String(decoding: bytes[8..<12], as: UTF8.self)
            switch riffType {
            case "WAVE": return .audio(format: "WAV")
            case "AVI ": return .video(format: "AVI")
            case "WEBP": return .image(format: "WebP")
            default: break
            }
        }

        // ISO BMFF containers ("ftyp" at offset 4): MP4, MOV, M4A, HEIC, AVIF.
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "mif1", "msf1": return .image(format: "HEIC")
            case "avif", "avis": return .image(format: "AVIF")
            case "M4A ": return .audio(format: "M4A")
            case "qt  ": return .video(format: "QuickTime")
            default: return .video(format: "MP4")
            }
        }

        // Font signatures: TrueType, OpenType (CFF), TrueType Collection, WOFF 1/2.
        if bytes.starts(with: [0x00, 0x01, 0x00, 0x00])
            || bytes.starts(with: Array("OTTO".utf8))
            || bytes.starts(with: Array("ttcf".utf8))
            || bytes.starts(with: Array("wOFF".utf8))
            || bytes.starts(with: Array("wOF2".utf8)) {
            return .font
        }

        if head.starts(with: Data("-----BEGIN ".utf8)) { return .pemCertificate }

        // Safetensors has no magic number: the first 8 bytes are a little-endian
        // header length and the header itself starts with '{'.
        if ext == "safetensors", bytes.count >= 9, bytes[8] == UInt8(ascii: "{") {
            return .safetensors
        }

        // DER certificates start with an ASN.1 SEQUENCE tag.
        if ["der", "cer", "crt"].contains(ext), bytes.first == 0x30 {
            return .derCertificate
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
