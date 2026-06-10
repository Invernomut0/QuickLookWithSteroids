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
            FolderPreviewView(document: document, nodes: folderSection)
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

        case .text(let content, _):
            GroupBox {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

// MARK: Folder Preview (Finder-style)

/// Full-height folder preview: a summary header plus a native List with
/// expand/collapse triangles, type icons, sizes, and modification dates —
/// matching the Finder "Name" sort (folders first, then files).
private struct FolderPreviewView: View {
    let document: PreviewDocument
    let nodes: [FolderNode]

    var body: some View {
        VStack(spacing: 0) {
            // Summary strip
            if let summarySection = document.sections.first,
               case .keyValues(_, let rows) = summarySection {
                HStack(spacing: 16) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text(document.title)
                        .font(.headline)
                    Spacer()
                    ForEach(rows.prefix(4)) { row in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(row.value)
                                .font(.callout.monospacedDigit())
                            Text(row.key)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                Divider()
            }

            // Column header
            HStack(spacing: 0) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .frame(width: 80, alignment: .trailing)
                Text("Modified")
                    .frame(width: 140, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Outline tree
            List(nodes, children: \.children) { node in
                FolderRowView(node: node)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 22)
        }
    }
}

private struct FolderRowView: View {
    let node: FolderNode

    var body: some View {
        HStack(spacing: 0) {
            // Icon + name
            HStack(spacing: 5) {
                Image(systemName: node.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size / item count
            Group {
                if node.isDirectory {
                    if let count = node.childCount, count > 0 {
                        Text("\(count) item\(count == 1 ? "" : "s")")
                    } else {
                        Text("—")
                    }
                } else if node.size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: node.size), countStyle: .file))
                } else {
                    Text("—")
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .trailing)

            // Modification date
            Group {
                if let date = node.modified {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
                } else {
                    Text("—")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 140, alignment: .trailing)
        }
        .font(.callout)
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
