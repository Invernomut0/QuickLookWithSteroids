import Foundation

/// ZIP-based application packages: JAR (manifest), APK, IPA (app Info.plist),
/// plus ZIP-based ML containers: NPZ (per-array headers) and PyTorch checkpoints.
public struct AppPackageRenderer: PreviewRenderer {
    public static let id = "app-package"
    public static let displayName = "App Packages"

    static let extensions: Set<String> = ["jar", "war", "apk", "ipa", "npz", "pt", "pth"]

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        file.kind == .zip && Self.extensions.contains(file.pathExtension)
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        switch file.pathExtension {
        case "jar", "war": return renderJAR(file, archive: archive)
        case "apk": return renderAPK(file, archive: archive)
        case "ipa": return renderIPA(file, archive: archive)
        case "npz": return renderNPZ(file, archive: archive)
        case "pt", "pth": return renderPyTorch(file, archive: archive)
        default: throw PreviewError.unsupportedType
        }
    }

    private func summary(_ archive: ZIPArchive, _ file: DetectedFile) -> [KeyValueRow] {
        [
            KeyValueRow("Entries", "\(archive.entries.filter { !$0.isDirectory }.count)"),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
    }

    private func renderJAR(_ file: DetectedFile, archive: ZIPArchive) -> PreviewDocument {
        var rows: [KeyValueRow] = []
        if let manifest = archive.entry(at: "META-INF/MANIFEST.MF"),
           let data = try? archive.extract(manifest, maxBytes: 1024 * 1024) {
            let text = String(decoding: data, as: UTF8.self)
            for line in text.components(separatedBy: .newlines).prefix(40) {
                let pair = line.split(separator: ":", maxSplits: 1)
                if pair.count == 2 {
                    rows.append(KeyValueRow(
                        pair[0].trimmingCharacters(in: .whitespaces),
                        pair[1].trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }
        let classCount = archive.entries.filter { $0.path.hasSuffix(".class") }.count
        var stats = summary(archive, file)
        stats.insert(KeyValueRow("Classes", "\(classCount)"), at: 0)

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: stats)]
        if !rows.isEmpty { sections.append(.keyValues(title: "Manifest", rows: rows)) }
        sections.append(.fileTree(title: "Contents", entries: Array(archive.archiveEntries.prefix(2000))))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Java Archive",
            iconSystemName: "cup.and.saucer",
            sections: sections
        )
    }

    private func renderAPK(_ file: DetectedFile, archive: ZIPArchive) -> PreviewDocument {
        var rows = summary(archive, file)
        let dexCount = archive.entries.filter { $0.path.hasSuffix(".dex") }.count
        rows.insert(KeyValueRow("DEX files", "\(dexCount)"), at: 0)
        let abis = Set(archive.entries.compactMap { entry -> String? in
            guard entry.path.hasPrefix("lib/") else { return nil }
            return entry.path.split(separator: "/").dropFirst().first.map(String.init)
        })
        if !abis.isEmpty {
            rows.insert(KeyValueRow("Native ABIs", abis.sorted().joined(separator: ", ")), at: 1)
        }
        rows.append(KeyValueRow("Note", "AndroidManifest.xml is binary-encoded (decoder planned)"))

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "Android Package",
            iconSystemName: "apps.iphone",
            sections: [
                .keyValues(title: "Summary", rows: rows),
                .fileTree(title: "Contents", entries: Array(archive.archiveEntries.prefix(2000))),
            ]
        )
    }

    private func renderIPA(_ file: DetectedFile, archive: ZIPArchive) -> PreviewDocument {
        var rows = summary(archive, file)
        // Payload/<Name>.app/Info.plist is a binary plist.
        if let plistEntry = archive.entries.first(where: {
            $0.path.hasPrefix("Payload/") && $0.path.hasSuffix(".app/Info.plist")
        }),
           let data = try? archive.extract(plistEntry, maxBytes: 4 * 1024 * 1024),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            var appRows: [KeyValueRow] = []
            let keys: [(String, String)] = [
                ("CFBundleDisplayName", "App name"), ("CFBundleName", "Bundle name"),
                ("CFBundleIdentifier", "Bundle ID"), ("CFBundleShortVersionString", "Version"),
                ("CFBundleVersion", "Build"), ("MinimumOSVersion", "Minimum iOS"),
            ]
            for (key, label) in keys {
                if let value = plist[key] as? String { appRows.append(KeyValueRow(label, value)) }
            }
            rows = appRows + rows
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "iOS App Package",
            iconSystemName: "apps.iphone",
            sections: [.keyValues(title: "App", rows: rows)]
        )
    }

    private func renderNPZ(_ file: DetectedFile, archive: ZIPArchive) -> PreviewDocument {
        // Each member is a .npy file; its header (first ~1 KB decompressed)
        // carries dtype and shape.
        var tableRows: [[String]] = []
        for entry in archive.entries.prefix(200) where entry.path.hasSuffix(".npy") {
            let name = String(entry.path.dropLast(4))
            guard let prefix = try? archive.extractPrefix(entry, maxBytes: 4096),
                  let info = NPYRenderer.headerInfo(from: prefix) else {
                tableRows.append([name, "?", "?"])
                continue
            }
            tableRows.append([name, info.dtype, info.shape])
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "NumPy Archive",
            iconSystemName: "square.grid.3x3",
            sections: [
                .keyValues(title: "Summary", rows: [
                    KeyValueRow("Arrays", "\(tableRows.count)"),
                    KeyValueRow("File size", Format.bytes(file.fileSize)),
                ]),
                .table(title: "Arrays", columns: ["Name", "Type", "Shape"], rows: tableRows),
            ]
        )
    }

    private func renderPyTorch(_ file: DetectedFile, archive: ZIPArchive) -> PreviewDocument {
        let storages = archive.entries.filter { $0.path.contains("/data/") && !$0.isDirectory }
        let totalData = storages.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "PyTorch Checkpoint",
            iconSystemName: "brain",
            sections: [
                .keyValues(title: "Summary", rows: [
                    KeyValueRow("Tensor storages", "\(storages.count)"),
                    KeyValueRow("Tensor data", Format.bytes(totalData)),
                    KeyValueRow("File size", Format.bytes(file.fileSize)),
                    KeyValueRow("Note", "Layer names live in data.pkl (pickle); not parsed for safety"),
                ]),
            ]
        )
    }
}
