import Foundation

/// The renderer-agnostic description of a preview. Renderers produce this;
/// the UI layer decides how to draw each section.
public struct PreviewDocument: Sendable {
    public var title: String
    public var subtitle: String?
    public var iconSystemName: String
    public var sections: [PreviewSection]

    public init(title: String, subtitle: String? = nil, iconSystemName: String, sections: [PreviewSection]) {
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.sections = sections
    }
}

public enum PreviewSection: Sendable {
    case keyValues(title: String?, rows: [KeyValueRow])
    case fileTree(title: String?, entries: [ArchiveEntry])
    case text(content: String, language: String?)
    case table(title: String?, columns: [String], rows: [[String]])
    case fontSpecimen(fontURL: URL)
    case image(URL)
    case note(String)
}

public struct KeyValueRow: Sendable, Identifiable {
    public let id = UUID()
    public var key: String
    public var value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

public struct ArchiveEntry: Sendable, Identifiable {
    public let id = UUID()
    public var path: String
    public var isDirectory: Bool
    public var uncompressedSize: UInt64
    public var compressedSize: UInt64
    public var modified: Date?

    public init(path: String, isDirectory: Bool, uncompressedSize: UInt64, compressedSize: UInt64, modified: Date?) {
        self.path = path
        self.isDirectory = isDirectory
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.modified = modified
    }
}

public enum PreviewError: Error, LocalizedError {
    case unsupportedType
    case corruptFile(String)
    case tooLarge(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: return "No renderer available for this file type."
        case .corruptFile(let detail): return "The file appears to be corrupt: \(detail)"
        case .tooLarge(let detail): return "The file is too large to preview: \(detail)"
        case .unreadable(let detail): return "The file could not be read: \(detail)"
        }
    }
}
