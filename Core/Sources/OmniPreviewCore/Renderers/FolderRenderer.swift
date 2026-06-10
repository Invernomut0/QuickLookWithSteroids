import Foundation

public struct FolderRenderer: PreviewRenderer {
    public static let id = "folder"
    public static let displayName = "Folder"

    static let maxDepth = 5
    static let maxNodes = 10_000

    static let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .isDirectoryKey, .isHiddenKey,
        .contentModificationDateKey, .isSymbolicLinkKey,
    ]

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool { file.kind == .folder }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        var nodeCount = 0
        let children = walk(url: file.url, depth: 0, count: &nodeCount)

        // Aggregate stats over the whole tree for the summary row.
        var totalFiles = 0
        var totalDirs = 0
        var totalSize: UInt64 = 0
        accumulate(children, files: &totalFiles, dirs: &totalDirs, size: &totalSize)

        var summaryRows = [
            KeyValueRow("Items", "\(totalFiles + totalDirs)"),
        ]
        if totalDirs > 0 { summaryRows.append(KeyValueRow("Subfolders", "\(totalDirs)")) }
        if totalFiles > 0 { summaryRows.append(KeyValueRow("Files", "\(totalFiles)")) }
        if totalSize > 0 { summaryRows.append(KeyValueRow("Total size", Format.bytes(totalSize))) }
        if nodeCount >= Self.maxNodes {
            summaryRows.append(KeyValueRow("Note", "Listing truncated at \(Self.maxNodes) items"))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Folder",
            iconSystemName: "folder",
            sections: [
                .keyValues(title: "Summary", rows: summaryRows),
                .folderTree(nodes: children),
            ]
        )
    }

    // MARK: Tree walker

    /// Returns the immediate (and recursive) children of `url`, stopping when
    /// `count` reaches `maxNodes` or `depth` reaches `maxDepth`.
    private func walk(url: URL, depth: Int, count: inout Int) -> [FolderNode] {
        guard depth < Self.maxDepth else { return [] }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            return []
        }

        // Folders first, then files — each group sorted case-insensitively,
        // matching the default Finder "Name" sort.
        let sorted = contents.sorted { a, b in
            let aDir = isDirectory(a)
            let bDir = isDirectory(b)
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        var nodes: [FolderNode] = []
        for childURL in sorted {
            guard count < Self.maxNodes else {
                nodes.append(FolderNode(
                    name: "… listing truncated", isDirectory: false,
                    size: 0, modified: nil, iconName: "ellipsis.circle", children: nil
                ))
                break
            }
            count += 1

            let values = (try? childURL.resourceValues(forKeys: Set(Self.resourceKeys)))
            let isDir = values?.isDirectory ?? false
            let size = values?.fileSize.flatMap { UInt64($0) } ?? 0
            let modified = values?.contentModificationDate

            var children: [FolderNode]?
            var childCount: Int?
            if isDir {
                let sub = walk(url: childURL, depth: depth + 1, count: &count)
                children = sub
                childCount = sub.filter { $0.iconName != "ellipsis.circle" }.count
            }

            nodes.append(FolderNode(
                name: childURL.lastPathComponent,
                isDirectory: isDir,
                size: size,
                childCount: childCount,
                modified: modified,
                iconName: Self.iconName(for: childURL, isDirectory: isDir),
                children: children
            ))
        }
        return nodes
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func accumulate(_ nodes: [FolderNode], files: inout Int, dirs: inout Int, size: inout UInt64) {
        for node in nodes {
            if node.isDirectory {
                dirs += 1
                if let children = node.children {
                    accumulate(children, files: &files, dirs: &dirs, size: &size)
                }
            } else {
                files += 1
                size += node.size
            }
        }
    }

    // MARK: Icon mapping

    static func iconName(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        // Images
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp",
             "svg", "avif", "psd", "psb", "icns", "ico", "exr", "jxl":
            return "photo"
        // Video
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv":
            return "film"
        // Audio
        case "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff":
            return "waveform"
        // PDFs & documents
        case "pdf":
            return "doc.richtext"
        case "docx", "doc", "odt", "pages", "rtf":
            return "doc.text"
        case "xlsx", "xls", "ods", "numbers", "csv":
            return "tablecells"
        case "pptx", "ppt", "odp", "key":
            return "rectangle.on.rectangle"
        // Archives
        case "zip", "gz", "tgz", "tar", "bz2", "xz", "7z", "rar",
             "cab", "iso", "dmg", "pkg", "deb", "rpm":
            return "doc.zipper"
        case "epub", "mobi", "azw3", "fb2", "cbz", "cbr":
            return "book.closed"
        // Code
        case "swift", "py", "js", "ts", "go", "rs", "c", "cpp", "cc",
             "h", "hpp", "java", "kt", "cs", "rb", "php", "lua", "sh",
             "bash", "zsh", "m", "mm":
            return "chevron.left.forwardslash.chevron.right"
        // Data / config
        case "json", "yaml", "yml", "toml", "xml", "plist", "ini", "env":
            return "doc.badge.gearshape"
        case "sql", "sqlite", "db", "sqlite3":
            return "cylinder.split.1x2"
        case "md", "markdown", "txt", "log":
            return "doc.text"
        // ML
        case "safetensors", "gguf", "onnx", "pt", "pth", "npy", "npz":
            return "brain"
        // 3D / CAD
        case "stl", "obj", "ply", "gltf", "glb", "usdz":
            return "cube"
        case "dxf", "dwg", "step", "stp":
            return "compass.drawing"
        // Fonts
        case "ttf", "otf", "woff", "woff2":
            return "textformat"
        // Certificates
        case "pem", "crt", "cer", "der", "p12", "pfx":
            return "checkmark.seal"
        // Executable / system
        case "app", "dylib", "framework", "xcframework":
            return "app.badge"
        case "exe", "dll":
            return "gear"
        default:
            return "doc"
        }
    }
}
