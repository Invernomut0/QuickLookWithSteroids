# OmniPreview — Session Context

**Repository**: https://github.com/Invernomut0/QuickLookWithSteroids  
**Local path**: `/Users/lorenzov/dev/QuickLookOnSteroids`  
**Current branch**: `main`  
**Last commit**: `14b893e` — "Fix video trim visible for free + Python loading hang"  
**Test suite**: 56/56 passing (`cd Core && swift test`)

---

## What This Project Is

macOS Quick Look extension framework named **OmniPreview**. Pressing Space on a file in Finder shows rich previews instead of generic icons. Built in pure Swift, zero third-party runtime dependencies, sandboxed, supports 100+ file formats.

### Architecture

```
Core/                         Swift package (no Xcode needed for logic)
  Sources/OmniPreviewCore/
    Detection/                FileTypeDetector (magic bytes + extension)
    Plugins/                  PreviewRenderer protocol, RendererRegistry
    Renderers/                29 renderer plugins (one file each)
    Caching/                  PreviewPipeline (content-identity NSCache)
    Support/                  DataReader, Decompressor, ZIPArchive, Format
    License/                  LicenseManager, ProTier, LockedRenderer
  Sources/OmniPreviewUI/      SwiftUI views (shared by app + extension)
    PreviewDocumentView.swift
    SyntaxHighlighter.swift   Token-based highlighter, 50+ languages
    CodeView.swift            NSTextView wrapper (NSViewRepresentable)
    MarkdownView.swift        Block-level Markdown renderer
App/                          Menu bar agent (LSUIElement=true)
  OmniPreviewApp.swift        @main, MenuBarExtra, ContentView
  AppDelegate.swift           applicationShouldTerminateAfterLastWindowClosed=false
  SettingsView.swift          General + Plugins + License tabs
  LicenseSettingsView.swift   Gumroad license activation UI
  ImageAnnotationView.swift   Pen/line/rect/text annotation editor
  VideoTrimSheet.swift        AVKit trim + AVAssetExportSession export
PreviewExtension/             QLPreviewingController (Space bar)
ThumbnailExtension/           QLThumbnailProvider (Finder icons)
project.yml                   XcodeGen definition (xcodeproj is generated)
scripts/                      build.sh, test.sh, generate.sh
```

### Build

```bash
cd /Users/lorenzov/dev/QuickLookOnSteroids
xcodegen generate                             # regenerate .xcodeproj
xcodebuild -project OmniPreview.xcodeproj -scheme OmniPreview -configuration Debug build
# builds to ~/Library/Developer/Xcode/DerivedData/OmniPreview-*/Build/Products/Debug/

# Launch the app (registers QL extensions with the system)
open ~/Library/Developer/Xcode/DerivedData/OmniPreview-*/Build/Products/Debug/OmniPreview.app

# Reset Quick Look cache after changes
qlmanage -r && qlmanage -r cache
```

### IDE Setup (VS Code)

```bash
brew install xcode-build-server
xcode-build-server config -project OmniPreview.xcodeproj -scheme OmniPreview
```

`buildServer.json` is gitignored. Without it, SourceKit-LSP shows phantom "Cannot find type" errors in App/ and extension sources (the build succeeds regardless).

---

## Free vs Pro Tiers

### Licensing

- **Product**: https://invernomuto2.gumroad.com/l/lghiqc
- **Product permalink**: `lghiqc` (used in Gumroad API calls)
- **Product ID code** (internal reference): `PrbYxrki-uQ8KxwsawhkDQ==`
- **LicenseManager** (`Core/Sources/OmniPreviewCore/License/LicenseManager.swift`):
  - Validates against `POST https://api.gumroad.com/v2/licenses/verify`
  - Stores result in `UserDefaults(suiteName: "com.omnipreview.license")` — shared between app and QL extension processes without App Groups
  - 7-day validity cache, 30-day grace period
  - `revalidateIfNeeded()` called in `AppDelegate.applicationDidFinishLaunching`

### Free tier (17 renderers + core UI)
All archives (ZIP/TAR/DMG/ISO/DEB…), SQLite, PDF, images (with AI metadata), fonts, certificates, INI/YAML/JSON, folder browser, GIS, torrents, database dumps, CAD, source code **as plain text**, Markdown **as plain text**, image annotation editor.

### Pro tier (12 renderers + 3 UI features)

**Renderer plugins** (`ProTier.proRendererIDs`):
- `safetensors` — Safetensors model inspection
- `gguf` — GGUF / LLM inspection
- `onnx` — ONNX models
- `npy` — NumPy arrays + NPZ
- `app-package` — JAR, APK, IPA, PyTorch
- `model3d` — Interactive 3D viewer (SceneKit)
- `office` — DOCX, XLSX, PPTX, ODT, ODS, ODP
- `ebook` — EPUB (with cover), MOBI, AZW3, FB2, CBZ
- `media` — Audio/video (duration, codecs, bitrate, tags)
- `data-file` — Parquet, HDF5, NetCDF, MATLAB, FITS
- `disk-image` — QCOW2, VMDK, VHDX
- `texture` — QOI, DDS, TGA, KTX/KTX2, HDR

**UI features** (gated in `PreviewDocumentView`):
- Syntax highlighting (colors via `SyntaxHighlighter`) → `TextSectionView.isPro` check
- Markdown formatted rendering (`MarkdownView`) → same check
- Video Trim & Export (`VideoTrimSheet`) → shown only when `isPro && previewedIsVideo`

### Locked UI
When a Pro renderer is accessed without license, `RendererRegistry.renderer(for:)` returns a `LockedRenderer` instead of the real renderer. This produces a `PreviewDocument` with a `.proLocked` section rendered as `ProLockedView` — shows format icon, "Get OmniPreview Pro →" link, and "activate in Settings" instructions.

For free text/source code: shown as plain monospace text (via `CodeView`, NOT SwiftUI `Text`) with a 1-line `ProNudge` banner above saying "Syntax Highlighting available with OmniPreview Pro".

---

## Key Design Decisions & Known Issues

### Critical: Always use CodeView (NSTextView), never Text() for large content
SwiftUI `Text(content)` with thousands of lines stalls the SwiftUI layout engine, causing the Quick Look extension to show an infinite loading spinner. All `.text` sections use `CodeView` (NSTextView wrapper) regardless of Pro status. The difference is only the `NSAttributedString` coloring.

### Quick Look UTI system: exact match only
QL does NOT follow UTI conformance hierarchy. `public.source-code` in `QLSupportedContentTypes` does NOT automatically cover `.py` files. Every UTI must be listed explicitly. Currently 109 UTIs declared.

Key verified UTIs (from `mdls`):
- `.py` → `public.python-script`
- `.swift` → `public.swift-source`
- `.m` → `public.objective-c-source` (NOT `com.apple.m-source`)
- `.ts` → `public.mpeg-2-transport-stream` (!) — overridden by our `com.omnipreview.typescript` import
- `.rb` → `public.ruby-script`
- `.php` → `public.php-script`
- `.go`, `.rs`, `.kt`, `.lua`, `.scss`, `.ts/.tsx/.jsx` → no Apple UTI, require custom imports

### LSUIElement = true
The app runs as a menu bar agent — no Dock icon, no Command-Tab entry. `applicationShouldTerminateAfterLastWindowClosed` returns `false` via `AppDelegate` so closing the tester window doesn't quit the app.

### Settings bug workaround
For LSUIElement apps, `SettingsLink` requires `NSApp.activate(ignoringOtherApps: true)` BEFORE calling `openSettings()`. About panel requires `NSApp.orderFrontStandardAboutPanel()` FIRST, then activate (reversed order prevents Settings from auto-restoring).

### ZIP entry extraction is bounded
`ZIPArchive.extractPrefix(entry:maxBytes:)` caps decompression output. Archive listings are parsed from the central directory only — entries are never inflated for the listing, making zip bombs structurally harmless.

### UserDefaults suite sharing
`UserDefaults(suiteName: "com.omnipreview.license")` is accessible by both app and extension processes without App Groups (data stored in `~/Library/Preferences/com.omnipreview.license.plist` via `cfprefsd`). No special entitlements needed.

---

## All 29 Renderers (in registry order)

```
FolderRenderer        .folder kinds
OfficeRenderer        .zip + DOCX/XLSX/PPTX/ODT ext  [PRO]
EbookRenderer         .zip/.rar/.mobi/.fb2 + epub/cbz/cbr ext  [PRO]
AppPackageRenderer    .zip + jar/war/apk/ipa/npz/pt/pth ext  [PRO]
GeoRenderer           .geo kinds + KMZ zip
ThreeDRenderer        .model3D kinds + USDZ zip  [PRO]
ZIPRenderer           .zip (generic fallback)
TARRenderer           .tar
GzipRenderer          .gzip (+ tar.gz contents via Decompressor)
XZRenderer            .xz (+ tar.xz contents)
ArchiveMetadataRenderer  .sevenZip/.rar/.bzip2/.cab/.iso/.dmg/.arArchive/.rpmPackage/.xar/.compoundFile
SQLiteRenderer        .sqlite
SafetensorsRenderer   .safetensors  [PRO]
GGUFRenderer          .gguf  [PRO]
ONNXRenderer          .onnx  [PRO]
NPYRenderer           .npy  [PRO]
PDFRenderer           .pdf
ImageRenderer         .image kinds
TextureRenderer       .texture kinds  [PRO]
MediaRenderer         .audio/.video kinds  [PRO]
DataFileRenderer      .dataFile kinds  [PRO]
DiskImageRenderer     .diskImage kinds  [PRO]
CADRenderer           .cad kinds
TorrentRenderer       .torrent
DumpRenderer          .sqlDump/.terraformState
CertificateRenderer   .pemCertificate/.derCertificate/.pkcs12
FontRenderer          .font
YAMLRenderer          .sourceCode(language: "YAML")
INIRenderer           .sourceCode(language: "INI") + ini/cfg/conf ext
SourceCodeRenderer    .sourceCode + .unknown (text sniff)
```

---

## Files Added/Modified This Session (by category)

### New files
- `Core/Sources/OmniPreviewCore/License/LicenseManager.swift`
- `Core/Sources/OmniPreviewCore/License/ProTier.swift`
- `Core/Sources/OmniPreviewCore/License/LockedRenderer.swift`
- `Core/Sources/OmniPreviewUI/SyntaxHighlighter.swift`
- `Core/Sources/OmniPreviewUI/CodeView.swift`
- `Core/Sources/OmniPreviewUI/MarkdownView.swift`
- `App/AppDelegate.swift`
- `App/LicenseSettingsView.swift`
- `App/VideoTrimSheet.swift`
- `App/ImageAnnotationView.swift`
- `Core/Sources/OmniPreviewCore/Support/Decompressor.swift`
- `Core/Sources/OmniPreviewCore/Support/ZIPArchive.swift`
- `Core/Sources/OmniPreviewCore/Renderers/YAMLRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/INIRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/FolderRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/TorrentRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/GeoRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/DiskImageRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/DataFileRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/ThreeDRenderer.swift`
- `Core/Sources/OmniPreviewCore/Renderers/TextureRenderer.swift`

### Key modified files
- `Core/Sources/OmniPreviewCore/Detection/FileTypeDetector.swift` — 50+ extensions in `sourceLanguages`, 45+ magic byte signatures
- `Core/Sources/OmniPreviewCore/Detection/FileKind.swift` — all new kind cases
- `Core/Sources/OmniPreviewCore/Plugins/RendererPlugin.swift` — Pro gate in `renderer(for:)`
- `Core/Sources/OmniPreviewCore/Plugins/PreviewModels.swift` — `FolderNode`, `.folderTree`, `.proLocked`, `.imageData`, `.model3D` sections
- `Core/Sources/OmniPreviewUI/PreviewDocumentView.swift` — all section renderers, `FolderPreviewView`, `TextSectionView`, `ProLockedView`, `ProNudge`, `Model3DView`
- `App/OmniPreviewApp.swift` — menu bar menu, ContentView with annotate + trim buttons
- `App/SettingsView.swift` — License tab added first
- `project.yml` — 109 UTIs, LSUIElement, network entitlement, custom UTI imports

---

## Roadmap (documented in docs/ROADMAP.md)

### Near-term
- TAR.GZ/XZ contents listing is already implemented via `Decompressor` — working
- RAR/7z actual contents listing → needs libarchive (would break zero-dependency property)
- ZIP64 support in `ZIPArchive`
- APK binary AndroidManifest decoding
- WOFF→sfnt unwrapping for live specimens
- Syntax highlighting for more niche languages

### Medium-term
- App Group entitlement (requires real team signing) for proper cross-process license sharing
- Disk cache for rendered previews (SQLite metadata index)
- MapKit preview for GIS files
- Waveform view for audio
- Git repository preview

### Known limitations
- GLB/glTF: statistics only, no interactive viewer (ModelIO has no glTF importer)
- MKV/WebM: detected and labeled, AVFoundation can't decode their streams fully
- ComfyUI AI metadata: PNG only (other formats store it differently)
- PKCS#12: container identification only (contents are password-encrypted)
- ZIP64: detected and rejected with clean error (not yet parsed)
