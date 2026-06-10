import SwiftUI
import CoreText
import SceneKit
import SceneKit.ModelIO
import ModelIO
import OmniPreviewCore

/// Renders a `PreviewDocument` with native typography, spacing, and
/// automatic dark/light adaptation. Shared by the Quick Look extension
/// and the host app.
public struct PreviewDocumentView: View {
    let document: PreviewDocument

    public init(document: PreviewDocument) {
        self.document = document
    }

    public var body: some View {
        // Folder previews get a dedicated full-height List view; all other
        // types use the generic scrollable section layout.
        if let folderSection = document.sections.compactMap({ if case .folderTree(let n) = $0 { return n } else { return nil } }).first {
            FolderPreviewView(
                document: document,
                nodes: folderSection,
                isArchive: document.iconSystemName == "doc.zipper"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        SectionView(section: section)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: document.iconSystemName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = document.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SectionView: View {
    let section: PreviewSection

    var body: some View {
        switch section {
        case .keyValues(let title, let rows):
            GroupBox(label: sectionLabel(title)) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.key)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(row.value)
                                .textSelection(.enabled)
                        }
                        .font(.callout)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .fileTree(let title, let entries):
            GroupBox(label: sectionLabel(title)) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries.prefix(2000)) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(entry.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if !entry.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.uncompressedSize), countStyle: .file))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(8)
            }

        case .text(let content, let language):
            TextSectionView(content: content, language: language)

        case .table(let title, let columns, let rows):
            GroupBox(label: sectionLabel(title)) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        ForEach(columns, id: \.self) { column in
                            Text(column).font(.callout.weight(.semibold))
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .fontSpecimen(let fontURL):
            GroupBox(label: sectionLabel("Specimen")) {
                FontSpecimenView(fontURL: fontURL)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

        case .imageData(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

        case .model3D(let url):
            Model3DView(url: url)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case .folderTree:
            // Handled at the top level by FolderPreviewView; not rendered here.
            EmptyView()

        case .proLocked(let formatName, let icon):
            ProLockedView(formatName: formatName, iconSystemName: icon)

        case .note(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String?) -> some View {
        if let title {
            Text(title).font(.headline)
        }
    }
}

/// Interactive 3D preview: ModelIO import → SceneKit scene with camera
/// controls (rotate, zoom, pan).
private struct Model3DView: View {
    let url: URL

    var body: some View {
        if let scene = Self.scene(for: url) {
            SceneView(
                scene: scene,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Interactive preview unavailable for this model")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static func scene(for url: URL) -> SCNScene? {
        guard MDLAsset.canImportFileExtension(url.pathExtension.lowercased()) else { return nil }
        let asset = MDLAsset(url: url)
        guard asset.count > 0 else { return nil }
        let scene = SCNScene(mdlAsset: asset)
        scene.background.contents = NSColor.windowBackgroundColor
        return scene
    }
}

// MARK: Text section — Pro gates syntax highlighting and Markdown rendering

private struct TextSectionView: View {
    let content: String
    let language: String?

    private var isPro: Bool { LicenseManager.shared.isProUnlocked }

    var body: some View {
        if isPro {
            proView
        } else {
            freeView
        }
    }

    // MARK: Pro path

    @ViewBuilder
    private var proView: some View {
        if language?.lowercased() == "markdown" {
            GroupBox {
                MarkdownView(source: content).padding(8)
            }
        } else if let language {
            let attributed = SyntaxHighlighter.highlight(content, language: language)
            let height = CodeView.estimatedHeight(for: content)
            GroupBox {
                CodeView(attributedString: attributed).frame(height: height)
            }
        } else {
            plainCodeBox
        }
    }

    // MARK: Free path — plain monospace text via NSTextView + upgrade nudge

    @ViewBuilder
    private var freeView: some View {
        if language != nil {
            VStack(spacing: 0) {
                ProNudge(feature: language?.lowercased() == "markdown"
                         ? "Formatted Markdown" : "Syntax Highlighting")
                plainCodeBox
            }
        } else {
            plainCodeBox
        }
    }

    // Always use NSTextView (CodeView) rather than SwiftUI Text — Text with
    // thousands of lines causes SwiftUI layout to stall, which manifests as
    // an infinite loading spinner in the Quick Look extension.
    private var plainCodeBox: some View {
        let plain = NSAttributedString(string: content, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        let height = CodeView.estimatedHeight(for: content)
        return GroupBox {
            CodeView(attributedString: plain)
                .frame(height: height)
        }
    }
}

/// A subtle one-line banner shown above free-tier text to hint that
/// a richer Pro view is available.
private struct ProNudge: View {
    let feature: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            Text("\(feature) available with OmniPreview Pro")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("PRO")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.75), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.06))
    }
}

// MARK: Finder-style tree view (folders + ZIP archives)

/// Column layout constants shared by the header and every row.
private enum FileListColumns {
    static let kind: CGFloat = 126
    static let size: CGFloat = 70
    static let date: CGFloat = 140
    /// Left padding to align with the List's built-in disclosure area.
    static let listInset: CGFloat = 8
}

/// Full-height Finder-style preview with disclosure triangles, Kind / Size /
/// Date Modified columns, alternating row tints, and relative dates.
/// Used for both folder previews and ZIP archive previews.
struct FolderPreviewView: View {
    let document: PreviewDocument
    let nodes: [FolderNode]
    /// True when showing a ZIP archive (changes the icon and status bar text).
    var isArchive: Bool = false

    private var summaryRows: [KeyValueRow] {
        guard case .keyValues(_, let rows) = document.sections.first else { return [] }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            columnHeader
            fileList
            statusBar
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Sub-views

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: isArchive ? "doc.zipper" : "folder.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isArchive ? Color.secondary : Color.accentColor)
                .font(.system(size: 16, weight: .medium))

            Text(document.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Compact stats badges
            HStack(spacing: 12) {
                ForEach(summaryRows.filter { !$0.key.hasPrefix("Note") && $0.key != "Space saved" }.prefix(4)) { row in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(row.value)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                        Text(row.key)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Material.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .padding(.leading, FileListColumns.listInset + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().frame(height: 14).opacity(0.4)
            Text("Kind")
                .frame(width: FileListColumns.kind, alignment: .leading)
                .padding(.leading, 8)
            Divider().frame(height: 14).opacity(0.4)
            Text("Size")
                .frame(width: FileListColumns.size, alignment: .trailing)
                .padding(.trailing, 8)
            Divider().frame(height: 14).opacity(0.4)
            Text("Date Modified")
                .frame(width: FileListColumns.date, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .overlay(Divider(), alignment: .bottom)
    }

    private var fileList: some View {
        List(nodes, children: \.children) { node in
            FolderRowView(node: node)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 20)
        .scrollContentBackground(.hidden)
    }

    private var statusBar: some View {
        HStack {
            Spacer()
            if let note = summaryRows.first(where: { $0.key == "Note" }) {
                Text(note.value)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let total = summaryRows.first { $0.key == "Items" }?.value
                    ?? summaryRows.first { $0.key == "Files" }?.value
                    ?? ""
                Text("\(total) item\(total == "1" ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 20)
        .background(Material.bar)
        .overlay(Divider(), alignment: .top)
    }
}

private struct FolderRowView: View {
    let node: FolderNode

    var body: some View {
        HStack(spacing: 0) {
            // Icon + Name
            Label {
                Text(node.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: node.iconName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                    .font(.system(size: 13))
                    .frame(width: 16, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, FileListColumns.listInset)

            // Kind
            Text(node.kindLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: FileListColumns.kind, alignment: .leading)
                .padding(.leading, 8)

            // Size
            Group {
                if node.isDirectory {
                    if let count = node.childCount {
                        Text("\(count) item\(count == 1 ? "" : "s")")
                    } else {
                        Text("—")
                    }
                } else if node.size > 0 {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(clamping: node.size), countStyle: .file))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: FileListColumns.size, alignment: .trailing)
            .padding(.trailing, 8)

            // Date Modified
            Text(node.modified.map { Self.formatDate($0) } ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: FileListColumns.date, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: 20)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
    }

    // Finder-style: relative for recent, absolute for older.
    private static func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 { return "Just now" }
        if calendar.isDateInToday(date) {
            return "Today at " + date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday at " + date.formatted(date: .omitted, time: .shortened)
        }
        if seconds < 7 * 24 * 3600 {
            // Within the last week: show weekday name.
            let weekday = date.formatted(Date.FormatStyle().weekday(.wide))
            return weekday + " at " + date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: Pro locked state

struct ProLockedView: View {
    let formatName: String
    let iconSystemName: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: iconSystemName)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.secondary, in: Circle())
                    .offset(x: 4, y: 4)
            }

            VStack(spacing: 6) {
                Text(formatName)
                    .font(.title3.weight(.semibold))

                Text("This format requires OmniPreview Pro.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Link(destination: URL(string: "https://invernomuto2.gumroad.com/l/lghiqc")!) {
                    Text("Get OmniPreview Pro →")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                }

                Text("Then activate your key in OmniPreview → Settings → License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

private struct FontSpecimenView: View {
    let fontURL: URL

    private static let pangram = "The quick brown fox jumps over the lazy dog 0123456789"

    var body: some View {
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([36, 24, 16, 12] as [CGFloat], id: \.self) { size in
                    Text(Self.pangram)
                        .font(Font(CTFontCreateWithFontDescriptor(descriptor, size, nil)))
                        .lineLimit(1)
                }
            }
        } else {
            Text("Specimen unavailable")
                .foregroundStyle(.secondary)
        }
    }
}
