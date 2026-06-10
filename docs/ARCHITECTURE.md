# OmniPreview Architecture

## Overview

```
┌────────────────────────────────────────────────────────────┐
│  Finder / Quick Look                                       │
│  ┌──────────────────────┐  ┌─────────────────────────┐     │
│  │ PreviewExtension     │  │ ThumbnailExtension      │     │
│  │ (QLPreviewing-       │  │ (QLThumbnailProvider)   │     │
│  │  Controller)         │  │                         │     │
│  └──────────┬───────────┘  └────────────┬────────────┘     │
└─────────────┼───────────────────────────┼──────────────────┘
              │                           │
       ┌──────▼───────────────────────────▼──────┐
       │ OmniPreviewUI (SwiftUI)                  │
       │ PreviewDocumentView — section renderers  │
       └──────────────────┬───────────────────────┘
                          │
       ┌──────────────────▼───────────────────────┐
       │ OmniPreviewCore                           │
       │                                           │
       │  PreviewPipeline ── memory cache          │
       │       │                                   │
       │  FileTypeDetector (magic bytes → ext)     │
       │       │                                   │
       │  RendererRegistry                         │
       │       │                                   │
       │  PreviewRenderer plugins (27)             │
       │  Archives: ZIP · TAR · Gzip/XZ · 7z/RAR/  │
       │   CAB/ISO/DMG/DEB/RPM/XAR/MSI metadata    │
       │  Documents: Office · eBooks · PDF         │
       │  ML/Data: Safetensors · GGUF · ONNX ·     │
       │   NPY/NPZ · PyTorch · Parquet/HDF5/FITS…  │
       │  Media: Image · Texture · Audio/Video     │
       │  3D/CAD/GIS: SceneKit viewer · DXF/STEP · │
       │   GeoJSON/KML/SHP · QCOW2/VMDK/VHDX       │
       │  Misc: SQLite · Dumps · Torrent · Certs · │
       │   Fonts · SourceCode · Terraform          │
       └───────────────────────────────────────────┘
```

## Layers

### Layer 1 — File Detection (`Detection/`)

`FileTypeDetector` reads the first 512 bytes and matches binary signatures
(magic bytes) before ever considering the filename. Extension matching is a
fallback for text formats that have no signature (source code) and a
*confirmation* for formats with weak signatures (safetensors, DER). A ZIP
renamed to `.txt` is still detected as a ZIP; a text file renamed to `.zip`
is not.

### Layer 2 — Preview Generation (`Caching/PreviewPipeline.swift`)

`PreviewPipeline` is the single entry point used by both extensions and the
host app: detect → look up renderer → render off the main thread → cache.
The cache key is `path|size|mtime`, so edits invalidate naturally.

### Layer 3 — Renderer Plugins (`Plugins/`, `Renderers/`)

Every file family implements `PreviewRenderer`:

```swift
public protocol PreviewRenderer: Sendable {
    static var id: String { get }
    static var displayName: String { get }
    func canRender(_ file: DetectedFile) -> Bool
    func render(_ file: DetectedFile) async throws -> PreviewDocument
}
```

`render` is `async` so renderers can use modern loading APIs (the media
renderer uses AVFoundation's async `load`); most renderers implement it
synchronously, which satisfies the requirement.

Renderers return a `PreviewDocument` — a UI-independent tree of sections
(key-value tables, file trees, text, data tables, font specimens). Renderers
never touch UI frameworks; `OmniPreviewUI` decides how each section looks.
This is what keeps a renderer testable with plain `swift test` and reusable
across preview, thumbnail, and the host app.

To add a format: write one file in `Renderers/`, add it to
`RendererRegistry.all`, declare its UTI in `project.yml` if macOS doesn't
know it, and add the UTI to the extension's `QLSupportedContentTypes`.

### Layer 4 — Caching

Phase 1 ships an `NSCache`-based memory cache keyed by content identity.
Planned (see ROADMAP): disk cache with an SQLite metadata index, versioned
entries, automatic cleanup.

### Layer 5 — Quick Look Integration

- `PreviewExtension` (`com.apple.quicklook.preview`): full Space-bar previews
  via `QLPreviewingController`, hosting the SwiftUI document view.
- `ThumbnailExtension` (`com.apple.quicklook.thumbnail`): fast icon cards via
  `QLThumbnailProvider`. Thumbnails draw type badges only — the <100 ms budget
  rules out heavy parsing here; thumbnails only ever use header reads.
- The host app's `Info.plist` imports UTIs for types macOS doesn't declare
  (`com.omnipreview.safetensors`, `.gguf`, `.sqlite`, `.woff`).

## Design Decisions

- **Core is a Swift package, app shell is XcodeGen.** Logic iterates with
  `swift test` in seconds; the `.xcodeproj` is generated and never committed.
- **No third-party dependencies in Phase 1.** ZIP central-directory parsing,
  GGUF, and safetensors are small enough to own outright; SQLite, CoreText,
  and Security ship with the OS. Dependencies (e.g. libarchive bindings for
  RAR/7z) will be isolated per-renderer when added.
- **Archives are listed, never extracted.** The ZIP renderer reads only the
  end-of-central-directory record and the central directory. Compressed data
  is never inflated, which eliminates the zip-bomb class entirely instead of
  mitigating it.
- **Every binary parser uses `DataReader`**, a bounds-checked sequential
  reader. Malformed input throws `PreviewError.corruptFile`; there is no code
  path that indexes a buffer unchecked.

## Known Limitations (Phase 1)

- ZIP64 archives are detected and rejected cleanly (not yet parsed).
- Source-code previews are plain monospaced text; syntax highlighting is
  planned (likely tree-sitter or a small regex highlighter per language).
- macOS gives system providers priority for types it already previews
  (e.g. `public.source-code`), so OmniPreview currently registers preview
  types it can genuinely take over.
- Thumbnails are type badges, not content miniatures.
