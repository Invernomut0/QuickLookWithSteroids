import Foundation

/// Header-level metadata for archive formats whose full listing would
/// require external libraries (7z, RAR) or heavyweight parsing (ISO, MSI).
/// DEB/ar archives get a real member listing (the format is trivial).
public struct ArchiveMetadataRenderer: PreviewRenderer {
    public static let id = "archive-metadata"
    public static let displayName = "Archive Formats"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        switch file.kind {
        case .sevenZip, .rar, .bzip2, .cab, .iso, .dmg, .arArchive, .rpmPackage, .xar, .compoundFile:
            return true
        default:
            return false
        }
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()

        switch file.kind {
        case .sevenZip:
            var reader = DataReader(head)
            try reader.skip(6)
            let major = try reader.readU8()
            let minor = try reader.readU8()
            return Self.simple(file, "7-Zip Archive", "doc.zipper", [
                KeyValueRow("Format version", "\(major).\(minor)"),
                KeyValueRow("Archive size", Format.bytes(file.fileSize)),
                KeyValueRow("Note", "Contents listing requires the 7z codec (planned via libarchive)"),
            ])

        case .rar:
            let version = head.count > 6 && head[6] == 0x01 ? "RAR 5.x" : "RAR 4.x"
            return Self.simple(file, "RAR Archive", "doc.zipper", [
                KeyValueRow("Format", version),
                KeyValueRow("Archive size", Format.bytes(file.fileSize)),
                KeyValueRow("Note", "Contents listing requires the RAR codec (planned via libarchive)"),
            ])

        case .bzip2:
            let level = head.count > 3 ? String(UnicodeScalar(head[3])) : "?"
            return Self.simple(file, "Bzip2 Archive", "doc.zipper", [
                KeyValueRow("Block size", "\(level)00 KB"),
                KeyValueRow("Compressed size", Format.bytes(file.fileSize)),
            ])

        case .cab:
            var reader = DataReader(head)
            try reader.skip(8) // signature + reserved
            let cabSize = try reader.readU32LE()
            try reader.skip(12) // reserved, first-file offset, reserved
            try reader.skip(2)  // version minor/major
            let folders = try reader.readU16LE()
            let files = try reader.readU16LE()
            return Self.simple(file, "Windows Cabinet", "doc.zipper", [
                KeyValueRow("Files", "\(files)"),
                KeyValueRow("Folders", "\(folders)"),
                KeyValueRow("Declared size", Format.bytes(UInt64(cabSize))),
            ])

        case .iso:
            // Primary volume descriptor at sector 16: identifiers at fixed offsets.
            var rows = [KeyValueRow("Image size", Format.bytes(file.fileSize))]
            if head.count > 32_768 + 1024 {
                let descriptor = head.subdata(in: 32_768..<(32_768 + 1024))
                func field(_ range: Range<Int>) -> String {
                    String(decoding: descriptor[range], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let volume = field(40..<72)
                if !volume.isEmpty { rows.insert(KeyValueRow("Volume name", volume), at: 0) }
                let publisher = field(318..<446)
                if !publisher.isEmpty { rows.append(KeyValueRow("Publisher", publisher)) }
                let application = field(574..<702)
                if !application.isEmpty { rows.append(KeyValueRow("Application", application)) }
            }
            return Self.simple(file, "ISO 9660 Disc Image", "opticaldisc", rows)

        case .dmg:
            return try Self.renderDMG(file, handle: handle)

        case .arArchive:
            return try Self.renderAr(file, head: head)

        case .rpmPackage:
            // The 96-byte lead carries a NUL-terminated package name at offset 10.
            var rows = [KeyValueRow("Package size", Format.bytes(file.fileSize))]
            if head.count >= 96 {
                let nameBytes = head[10..<76].prefix { $0 != 0 }
                let name = String(decoding: nameBytes, as: UTF8.self)
                if !name.isEmpty { rows.insert(KeyValueRow("Package", name), at: 0) }
                rows.append(KeyValueRow("Type", head[7] == 0 ? "Binary" : "Source"))
            }
            return Self.simple(file, "RPM Package", "shippingbox", rows)

        case .xar:
            var reader = DataReader(head)
            try reader.skip(4)
            let headerSize = try reader.readU16LE().byteSwapped // xar header is big-endian
            _ = headerSize
            try reader.skip(2)
            var rows = [KeyValueRow("Package size", Format.bytes(file.fileSize))]
            rows.append(KeyValueRow("Format", "xar (macOS installer package)"))
            return Self.simple(file, "Installer Package", "shippingbox", rows)

        case .compoundFile:
            let label: String
            switch file.pathExtension {
            case "msi": label = "Windows Installer (MSI)"
            case "doc": label = "Word 97–2003 Document"
            case "xls": label = "Excel 97–2003 Workbook"
            case "ppt": label = "PowerPoint 97–2003 Presentation"
            default: label = "Compound File (OLE2)"
            }
            return Self.simple(file, label, "doc", [
                KeyValueRow("Container", "Compound File Binary (CFB)"),
                KeyValueRow("File size", Format.bytes(file.fileSize)),
            ])

        default:
            throw PreviewError.unsupportedType
        }
    }

    /// DMG images end with a 512-byte big-endian "koly" trailer pointing at
    /// an XML property list that describes the partitions (blkx entries).
    private static func renderDMG(_ file: DetectedFile, handle: FileHandle) throws -> PreviewDocument {
        guard file.fileSize >= 512 else { throw PreviewError.corruptFile("file too small for a DMG") }
        try handle.seek(toOffset: file.fileSize - 512)
        let trailer = try handle.read(upToCount: 512) ?? Data()
        guard trailer.starts(with: Array("koly".utf8)) else {
            throw PreviewError.corruptFile("missing koly trailer — not a UDIF disk image")
        }

        func u64BE(at offset: Int) throws -> UInt64 {
            var reader = DataReader(trailer)
            try reader.skip(offset)
            let high = try reader.readU32BE()
            let low = try reader.readU32BE()
            return UInt64(high) << 32 | UInt64(low)
        }
        var versionReader = DataReader(trailer)
        try versionReader.skip(4)
        let version = try versionReader.readU32BE()
        let xmlOffset = try u64BE(at: 0xD8)
        let xmlLength = try u64BE(at: 0xE0)
        let sectors = try u64BE(at: 0x1EC)

        var rows = [
            KeyValueRow("Uncompressed size", Format.bytes(sectors * 512)),
            KeyValueRow("Image size", Format.bytes(file.fileSize)),
            KeyValueRow("UDIF version", "\(version)"),
        ]

        // Partition names from the blkx resource list.
        var partitionRows: [KeyValueRow] = []
        if xmlLength > 0, xmlLength <= 32 * 1024 * 1024, xmlOffset + xmlLength <= file.fileSize {
            try handle.seek(toOffset: xmlOffset)
            if let xmlData = try handle.read(upToCount: Int(xmlLength)),
               let plist = try? PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any],
               let resourceFork = plist["resource-fork"] as? [String: Any],
               let blkx = resourceFork["blkx"] as? [[String: Any]] {
                rows.append(KeyValueRow("Partitions", "\(blkx.count)"))
                for (index, block) in blkx.prefix(32).enumerated() {
                    let name = (block["Name"] as? String)?
                        .trimmingCharacters(in: .whitespaces) ?? "Partition \(index)"
                    partitionRows.append(KeyValueRow("\(index)", name))
                }
            }
        }

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: rows)]
        if !partitionRows.isEmpty {
            sections.append(.keyValues(title: "Partitions", rows: partitionRows))
        }

        // Attempt to mount the DMG read-only and list its contents.
        let fileEntries = Self.listDMGContents(file.url)
        if !fileEntries.isEmpty {
            sections.append(.fileTree(title: "Contents", entries: fileEntries))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Apple Disk Image",
            iconSystemName: "externaldrive",
            sections: sections
        )
    }

    /// Mounts the DMG temporarily (read-only, no Finder visibility) and
    /// enumerates the volume contents, then immediately detaches it.
    /// Returns an empty array if mounting fails (e.g. encrypted DMG, sandbox
    /// restriction, or insufficient permissions).
    private static func listDMGContents(_ url: URL) -> [ArchiveEntry] {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-dmg-\(UUID().uuidString)")

        // Mount: read-only, no Finder visibility, no verification (faster).
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = [
            "attach", url.path,
            "-readonly", "-nobrowse", "-noverify",
            "-mountpoint", mountPoint.path
        ]
        attachProcess.standardOutput = FileHandle.nullDevice
        attachProcess.standardError = FileHandle.nullDevice

        do {
            try attachProcess.run()
            attachProcess.waitUntilExit()
        } catch {
            return []
        }
        guard attachProcess.terminationStatus == 0 else { return [] }

        defer {
            // Always detach — even if enumeration fails.
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: mountPoint,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [ArchiveEntry] = []
        let mountPath = mountPoint.path
        let cap = 500 // Don't enumerate huge volumes forever.

        while let itemURL = enumerator.nextObject() as? URL, entries.count < cap {
            let relativePath = String(itemURL.path.dropFirst(mountPath.count + 1))
            guard !relativePath.isEmpty else { continue }
            let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            let size = UInt64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate
            entries.append(ArchiveEntry(
                path: relativePath,
                isDirectory: isDir,
                uncompressedSize: size,
                compressedSize: 0,
                modified: modified
            ))
        }
        return entries
    }

    /// Unix ar archives (.deb packages, .a static libraries): 60-byte
    /// member headers, trivially listable.
    private static func renderAr(_ file: DetectedFile, head: Data) throws -> PreviewDocument {
        let bytes = [UInt8](head)
        var entries: [ArchiveEntry] = []
        var offset = 8
        var isDeb = false

        while offset + 60 <= bytes.count, entries.count < 200 {
            let nameField = String(decoding: bytes[offset..<offset + 16], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            let sizeField = String(decoding: bytes[offset + 48..<offset + 58], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            guard let size = UInt64(sizeField) else { break }
            let name = nameField.hasSuffix("/") ? String(nameField.dropLast()) : nameField
            if name == "debian-binary" { isDeb = true }
            entries.append(ArchiveEntry(
                path: name, isDirectory: false,
                uncompressedSize: size, compressedSize: size, modified: nil
            ))
            // Member data is 2-byte aligned.
            let advance = 60 + Int(size) + (size % 2 == 0 ? 0 : 1)
            offset += advance
        }

        let subtitle = isDeb ? "Debian Package" : "Unix Archive (ar)"
        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: subtitle,
            iconSystemName: isDeb ? "shippingbox" : "doc.zipper",
            sections: [
                .keyValues(title: "Summary", rows: [
                    KeyValueRow("Members", "\(entries.count)"),
                    KeyValueRow("Archive size", Format.bytes(file.fileSize)),
                ]),
                .fileTree(title: "Members", entries: entries),
            ]
        )
    }

    static func simple(_ file: DetectedFile, _ subtitle: String, _ icon: String,
                       _ rows: [KeyValueRow]) -> PreviewDocument {
        PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: subtitle,
            iconSystemName: icon,
            sections: [.keyValues(title: "Summary", rows: rows)]
        )
    }
}
