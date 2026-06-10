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
    case folderTree(nodes: [FolderNode])
    case text(content: String, language: String?)
    case table(title: String?, columns: [String], rows: [[String]])
    case fontSpecimen(fontURL: URL)
    case image(URL)
    case imageData(Data)
    case model3D(URL)
    case proLocked(formatName: String, iconSystemName: String)
    case note(String)
}

/// A node in a folder tree. Directories carry a `children` array (possibly
/// empty after hitting the depth/count cap); files have `nil` children.
public final class FolderNode: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let isDirectory: Bool
    /// Byte size for files; 0 for directories.
    public let size: UInt64
    /// Number of immediate visible children (directories only).
    public let childCount: Int?
    public let modified: Date?
    public let iconName: String
    /// Human-readable kind label (e.g. "JPEG Image", "Swift Source", "Folder").
    public let kindLabel: String
    /// `nil` for files; non-nil (possibly empty) for directories.
    public let children: [FolderNode]?

    public init(
        name: String, isDirectory: Bool, size: UInt64,
        childCount: Int? = nil, modified: Date?, iconName: String,
        kindLabel: String = "",
        children: [FolderNode]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.childCount = childCount
        self.modified = modified
        self.iconName = iconName
        self.kindLabel = kindLabel.isEmpty ? (isDirectory ? "Folder" : "Document") : kindLabel
        self.children = children
    }
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
