import Foundation

/// File families OmniPreview understands. Detection is signature-first
/// (magic bytes), extension-second — never extension-only for binary formats.
public enum FileKind: Equatable, Sendable {
    case zip
    case tar
    case gzip
    case sevenZip
    case rar
    case xz
    case sqlite
    case safetensors
    case gguf
    case pemCertificate
    case derCertificate
    case font
    case sourceCode(language: String)
    case pdf
    case image(format: String)
    case audio(format: String)
    case video(format: String)
    case npy
    case unknown
}

public struct DetectedFile: Sendable {
    public let url: URL
    public let kind: FileKind
    public let fileSize: UInt64

    public init(url: URL, kind: FileKind, fileSize: UInt64) {
        self.url = url
        self.kind = kind
        self.fileSize = fileSize
    }
}
