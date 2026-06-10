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

        let sorted = contents.sorted { a, b in
            let aDir = isDirectory(a)
            let bDir = isDirectory(b)
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        var nodes: [FolderNode] = []
        for childURL in sorted {
            guard count < Self.maxNodes else {
                nodes.append(truncationNode)
                break
            }
            count += 1

            let values = try? childURL.resourceValues(forKeys: Set(Self.resourceKeys))
            let isDir = values?.isDirectory ?? false
            let size = values?.fileSize.flatMap { UInt64($0) } ?? 0
            let modified = values?.contentModificationDate

            var children: [FolderNode]?
            var childCount: Int?
            if isDir {
                let sub = walk(url: childURL, depth: depth + 1, count: &count)
                children = sub
                childCount = sub.filter { !$0.name.hasPrefix("…") }.count
            }

            let ext = childURL.pathExtension.lowercased()
            nodes.append(FolderNode(
                name: childURL.lastPathComponent,
                isDirectory: isDir,
                size: size,
                childCount: childCount,
                modified: modified,
                iconName: Self.iconName(ext: ext, isDirectory: isDir),
                kindLabel: Self.kindLabel(ext: ext, isDirectory: isDir),
                children: children
            ))
        }
        return nodes
    }

    private var truncationNode: FolderNode {
        FolderNode(name: "… listing truncated", isDirectory: false,
                   size: 0, modified: nil, iconName: "ellipsis.circle",
                   kindLabel: "")
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

    // MARK: Icon and kind label (keyed by lowercased extension)

    public static func iconName(ext: String, isDirectory: Bool) -> String {
        if isDirectory { return "folder.fill" }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp",
             "svg", "avif", "psd", "psb", "icns", "ico", "exr", "jxl": return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv": return "film"
        case "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff": return "waveform"
        case "pdf": return "doc.richtext"
        case "docx", "doc", "odt", "pages", "rtf": return "doc.text"
        case "xlsx", "xls", "ods", "numbers", "csv": return "tablecells"
        case "pptx", "ppt", "odp", "key": return "rectangle.on.rectangle"
        case "zip", "gz", "tgz", "tar", "bz2", "xz", "7z", "rar",
             "cab", "iso", "dmg", "pkg", "deb", "rpm": return "doc.zipper"
        case "epub", "mobi", "azw3", "fb2", "cbz", "cbr": return "book.closed"
        case "swift", "py", "js", "ts", "go", "rs", "c", "cpp", "cc",
             "h", "hpp", "java", "kt", "cs", "rb", "php", "lua", "sh",
             "bash", "zsh", "m", "mm": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "xml", "plist",
             "ini", "cfg", "conf", "env": return "doc.badge.gearshape"
        case "sql", "sqlite", "db", "sqlite3": return "cylinder.split.1x2"
        case "md", "markdown", "txt", "log": return "doc.text"
        case "safetensors", "gguf", "onnx", "pt", "pth", "npy", "npz": return "brain"
        case "stl", "obj", "ply", "gltf", "glb", "usdz": return "cube"
        case "dxf", "dwg", "step", "stp": return "compass.drawing"
        case "ttf", "otf", "woff", "woff2": return "textformat"
        case "pem", "crt", "cer", "der", "p12", "pfx": return "checkmark.seal"
        case "app", "dylib", "framework", "xcframework": return "app.badge"
        case "exe", "dll": return "gear"
        default: return "doc"
        }
    }

    // Convenience overload for callers that have a URL.
    public static func iconName(for url: URL, isDirectory: Bool) -> String {
        iconName(ext: url.pathExtension.lowercased(), isDirectory: isDirectory)
    }

    public static func kindLabel(ext: String, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        switch ext {
        case "jpg", "jpeg": return "JPEG Image"
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        case "heic", "heif": return "HEIC Image"
        case "webp": return "WebP Image"
        case "tiff": return "TIFF Image"
        case "bmp": return "Bitmap Image"
        case "psd": return "Photoshop Document"
        case "svg": return "SVG Image"
        case "exr": return "EXR Image"
        case "jxl": return "JPEG XL Image"
        case "icns": return "Icon Image"
        case "ico": return "Icon"
        case "avif": return "AVIF Image"
        case "mp4", "m4v": return "MPEG-4 Movie"
        case "mov": return "QuickTime Movie"
        case "avi": return "AVI Movie"
        case "mkv": return "Matroska Video"
        case "webm": return "WebM Video"
        case "mp3": return "MP3 Audio"
        case "m4a": return "AAC Audio"
        case "flac": return "FLAC Audio"
        case "wav": return "WAV Audio"
        case "aac": return "AAC Audio"
        case "ogg": return "Ogg Audio"
        case "opus": return "Opus Audio"
        case "aiff": return "AIFF Audio"
        case "pdf": return "PDF Document"
        case "docx": return "Word Document"
        case "doc": return "Word 97 Document"
        case "odt": return "OpenDocument Text"
        case "pages": return "Pages Document"
        case "rtf": return "Rich Text"
        case "xlsx": return "Excel Spreadsheet"
        case "xls": return "Excel 97 Spreadsheet"
        case "ods": return "OpenDocument Spreadsheet"
        case "numbers": return "Numbers Spreadsheet"
        case "csv": return "CSV"
        case "pptx": return "PowerPoint Presentation"
        case "ppt": return "PowerPoint 97 Presentation"
        case "odp": return "OpenDocument Presentation"
        case "key": return "Keynote Presentation"
        case "zip": return "ZIP Archive"
        case "tar": return "TAR Archive"
        case "gz", "tgz": return "Gzip Archive"
        case "bz2": return "Bzip2 Archive"
        case "xz": return "XZ Archive"
        case "7z": return "7-Zip Archive"
        case "rar": return "RAR Archive"
        case "dmg": return "Disk Image"
        case "iso": return "ISO Image"
        case "pkg": return "Installer Package"
        case "deb": return "Debian Package"
        case "rpm": return "RPM Package"
        case "epub": return "EPUB eBook"
        case "mobi", "azw3": return "Kindle eBook"
        case "fb2": return "FictionBook"
        case "cbz": return "Comic Book (ZIP)"
        case "cbr": return "Comic Book (RAR)"
        case "swift": return "Swift Source"
        case "py": return "Python Script"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "go": return "Go Source"
        case "rs": return "Rust Source"
        case "c": return "C Source"
        case "cpp", "cc": return "C++ Source"
        case "h": return "C Header"
        case "hpp": return "C++ Header"
        case "java": return "Java Source"
        case "kt": return "Kotlin Source"
        case "cs": return "C# Source"
        case "rb": return "Ruby Script"
        case "php": return "PHP Script"
        case "lua": return "Lua Script"
        case "sh", "bash", "zsh": return "Shell Script"
        case "m": return "Objective-C Source"
        case "mm": return "Objective-C++ Source"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "xml": return "XML"
        case "plist": return "Property List"
        case "ini", "cfg", "conf": return "Config File"
        case "env": return "Environment File"
        case "md", "markdown": return "Markdown"
        case "txt": return "Plain Text"
        case "log": return "Log File"
        case "sql": return "SQL Script"
        case "sqlite", "db", "sqlite3": return "SQLite Database"
        case "safetensors": return "Safetensors Model"
        case "gguf": return "GGUF Model"
        case "onnx": return "ONNX Model"
        case "pt", "pth": return "PyTorch Checkpoint"
        case "npy": return "NumPy Array"
        case "npz": return "NumPy Archive"
        case "stl": return "STL Model"
        case "obj": return "OBJ Model"
        case "ply": return "PLY Model"
        case "gltf": return "glTF Scene"
        case "glb": return "GLB Scene"
        case "usdz": return "USDZ Scene"
        case "dxf": return "DXF Drawing"
        case "dwg": return "AutoCAD Drawing"
        case "step", "stp": return "STEP Model"
        case "ttf": return "TrueType Font"
        case "otf": return "OpenType Font"
        case "woff": return "Web Font"
        case "woff2": return "Web Font 2"
        case "pem", "crt": return "Certificate"
        case "cer": return "Certificate"
        case "der": return "Certificate (DER)"
        case "p12", "pfx": return "PKCS#12 Identity"
        case "app": return "Application"
        case "dylib": return "Dynamic Library"
        case "framework": return "Framework"
        case "exe": return "Windows App"
        case "dll": return "Windows Library"
        default: return ext.isEmpty ? "Document" : "\(ext.uppercased()) File"
        }
    }
}
