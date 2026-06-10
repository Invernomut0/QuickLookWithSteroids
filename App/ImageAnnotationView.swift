import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Quick image markup: pen, line, rectangle, and text tools with color and
/// stroke-width controls, undo/clear, and PNG export at native resolution.
/// Coordinates are stored normalized (0…1), so drawing scales losslessly
/// between the on-screen canvas and the exported image.

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case line = "Line"
    case rectangle = "Rectangle"
    case text = "Text"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .pen: return "pencil"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }
}

struct Annotation: Identifiable {
    enum Shape {
        case stroke(points: [CGPoint])
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case text(String, at: CGPoint)
    }

    let id = UUID()
    var shape: Shape
    var color: Color
    /// Stroke width / text height as a fraction of the canvas height.
    var weight: CGFloat
}

struct ImageAnnotationView: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var annotations: [Annotation] = []
    @State private var tool: AnnotationTool = .pen
    @State private var color: Color = .red
    @State private var strokeWidth: CGFloat = 3 // points at display size
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var livePoints: [CGPoint] = []
    @State private var pendingText: String = ""
    @State private var pendingTextAnchor: CGPoint? // normalized
    @State private var exportMessage: String?

    private let image: NSImage?

    init(imageURL: URL) {
        self.imageURL = imageURL
        self.image = NSImage(contentsOf: imageURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let image {
                GeometryReader { geometry in
                    let canvasSize = fittedSize(image: image.size, in: geometry.size)
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)
                        canvas(image: image, size: canvasSize)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                }
            } else {
                Text("Could not load image")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Image(systemName: tool.symbol).tag(tool)
                        .help(tool.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()

            ColorPicker("Color", selection: $color)
                .labelsHidden()

            HStack(spacing: 4) {
                Image(systemName: "lineweight").foregroundStyle(.secondary)
                Slider(value: $strokeWidth, in: 1...12)
                    .frame(width: 90)
            }

            Spacer()

            Button {
                _ = annotations.popLast()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Undo")
                .disabled(annotations.isEmpty)

            Button {
                annotations.removeAll()
            } label: { Image(systemName: "trash") }
                .help("Remove all annotations")
                .disabled(annotations.isEmpty)

            if let exportMessage {
                Text(exportMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Save PNG…") { savePNG() }
                .keyboardShortcut("s")

            Button("Done") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(10)
    }

    // MARK: Canvas

    private func canvas(image: NSImage, size: CGSize) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)

            AnnotationCanvas(
                annotations: annotations,
                liveAnnotation: liveAnnotation(canvasSize: size)
            )
        }
        .overlay(textEntryOverlay(size: size))
        .contentShape(Rectangle())
        .gesture(drawGesture(size: size))
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = normalize(value.location, in: size)
                if dragStart == nil {
                    dragStart = normalize(value.startLocation, in: size)
                    livePoints = []
                }
                dragCurrent = point
                if tool == .pen { livePoints.append(point) }
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil; livePoints = [] }
                let end = normalize(value.location, in: size)
                guard let start = dragStart else { return }
                let weight = strokeWidth / size.height

                switch tool {
                case .pen:
                    guard livePoints.count > 1 else { return }
                    annotations.append(Annotation(shape: .stroke(points: livePoints), color: color, weight: weight))
                case .line:
                    annotations.append(Annotation(shape: .line(from: start, to: end), color: color, weight: weight))
                case .rectangle:
                    annotations.append(Annotation(shape: .rectangle(normalizedRect(start, end)), color: color, weight: weight))
                case .text:
                    pendingTextAnchor = end
                    pendingText = ""
                }
            }
    }

    @ViewBuilder
    private func textEntryOverlay(size: CGSize) -> some View {
        if let anchor = pendingTextAnchor {
            TextField("Text", text: $pendingText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .position(x: anchor.x * size.width, y: anchor.y * size.height)
                .onSubmit {
                    if !pendingText.isEmpty {
                        // Text height scales with stroke width for a natural size.
                        let weight = (strokeWidth * 6 + 10) / size.height
                        annotations.append(Annotation(
                            shape: .text(pendingText, at: anchor), color: color, weight: weight
                        ))
                    }
                    pendingTextAnchor = nil
                }
                .onExitCommand { pendingTextAnchor = nil }
        }
    }

    private func liveAnnotation(canvasSize: CGSize) -> Annotation? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let weight = strokeWidth / canvasSize.height
        switch tool {
        case .pen:
            return livePoints.count > 1
                ? Annotation(shape: .stroke(points: livePoints), color: color, weight: weight)
                : nil
        case .line:
            return Annotation(shape: .line(from: start, to: current), color: color, weight: weight)
        case .rectangle:
            return Annotation(shape: .rectangle(normalizedRect(start, current)), color: color, weight: weight)
        case .text:
            return nil
        }
    }

    // MARK: Geometry helpers

    private func fittedSize(image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let scale = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x / size.width, 0), 1),
            y: min(max(point.y / size.height, 0), 1)
        )
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y)
        )
    }

    // MARK: Export

    private func savePNG() {
        guard let image else { return }
        // Render at native pixel resolution.
        let pixelSize = image.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size

        let renderer = ImageRenderer(content:
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                AnnotationCanvas(annotations: annotations, liveAnnotation: nil)
            }
            .frame(width: pixelSize.width, height: pixelSize.height)
        )
        renderer.scale = 1
        guard let rendered = renderer.nsImage,
              let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            exportMessage = "Export failed"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = imageURL.deletingPathExtension().lastPathComponent + "-annotated.png"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try png.write(to: url)
                exportMessage = "Saved"
            } catch {
                exportMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Draws annotations (normalized coordinates) scaled to the current size.
/// Shared between the interactive canvas and the high-resolution export.
struct AnnotationCanvas: View {
    let annotations: [Annotation]
    let liveAnnotation: Annotation?

    var body: some View {
        Canvas { context, size in
            for annotation in annotations {
                draw(annotation, in: &context, size: size)
            }
            if let liveAnnotation {
                draw(liveAnnotation, in: &context, size: size)
            }
        }
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, size: CGSize) {
        let lineWidth = max(annotation.weight * size.height, 0.5)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

        switch annotation.shape {
        case .stroke(let points):
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: point(points[0]))
            for p in points.dropFirst() { path.addLine(to: point(p)) }
            context.stroke(path, with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        case .line(let from, let to):
            var path = Path()
            path.move(to: point(from))
            path.addLine(to: point(to))
            context.stroke(path, with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .rectangle(let rect):
            let scaled = CGRect(
                x: rect.minX * size.width, y: rect.minY * size.height,
                width: rect.width * size.width, height: rect.height * size.height
            )
            context.stroke(Path(scaled), with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

        case .text(let string, let anchor):
            let fontSize = annotation.weight * size.height
            let text = Text(string)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(annotation.color)
            context.draw(text, at: point(anchor), anchor: .leading)
        }
    }
}
