import SwiftUI
import CoreText
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
