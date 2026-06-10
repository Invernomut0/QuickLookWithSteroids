# OmniPreview

A native macOS Quick Look extension framework that brings rich previews to file types macOS does not support — archives, ML model files, databases, certificates, fonts, and more. Pure Swift, sandboxed, no Electron, no WebViews.

## Status

**27 renderer plugins covering 100+ file formats**, all native Swift with zero third-party dependencies:

| Family | Formats | Preview |
|---|---|---|
| ZIP | `.zip`, … | File tree, sizes, compression ratio — listing never decompresses |
| TAR | `.tar` | File tree (memory-mapped, GNU long names) |
| Compressed TAR | `.tar.gz`, `.tgz`, `.tar.xz`, `.txz` | Full contents listing via bounded decompression |
| Gzip / XZ / BZ2 | `.gz`, `.xz`, `.bz2` | Header metadata (original name, date, OS) |
| Other archives | 7z, RAR, CAB, ISO, DMG, DEB, RPM, PKG (xar), MSI | Format-specific header metadata; DEB/ar gets a member listing, ISO volume info, DMG uncompressed size |
| Office | DOCX, XLSX, PPTX, ODT, ODS, ODP | Title/author, page/word/slide counts, sheet names, embedded thumbnail |
| eBooks | EPUB, MOBI, AZW3, FB2, CBZ, CBR | Cover image, title/author/language, spine/page counts |
| App packages | JAR, WAR, APK, IPA | Manifest key-values, class/DEX counts, native ABIs, iOS app Info.plist |
| SQLite | `.sqlite`, `.db`, `.sqlite3` | Schema, tables, column/row counts (read-only, `immutable=1`) |
| DB dumps | PostgreSQL (plain + custom), MySQL | Table list, statement counts, dump version |
| ML models | Safetensors, GGUF, ONNX, NPY, NPZ, PyTorch | Tensors/dtypes/shapes, architecture, quantization, producer |
| Scientific | Parquet, Arrow, DuckDB, HDF5, NetCDF, MATLAB, FITS | Format/version metadata; NetCDF dimensions, FITS header cards |
| PDF | `.pdf` | Page count/size, document info, bookmarks, encryption |
| Images | PNG, JPEG, GIF, TIFF, WebP, HEIC, AVIF, PSD, ICNS, ICO, EXR, JPEG XL | Picture, dimensions, color, EXIF — plus **AI generation metadata** (A1111/Forge, ComfyUI) from PNG chunks |
| Camera RAW | CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF, DNG | Decoded preview + camera EXIF via ImageIO |
| Textures | QOI, DDS, TGA, KTX, KTX2, Radiance HDR | Dimensions, formats, mip levels |
| Audio/Video | MP3, FLAC, WAV, Ogg, M4A, MP4, MOV, AVI, MKV/WebM* | Duration, codecs, resolution, fps, bitrate, tags |
| 3D models | STL, OBJ, PLY, USDZ, GLB, glTF | **Interactive rotate/zoom viewer** (SceneKit) + geometry statistics |
| CAD | DXF, DWG, STEP, IGES | Entity counts, AutoCAD version, STEP schema |
| GIS | GeoJSON, KML, KMZ, Shapefile | Feature/geometry counts, bounding boxes, placemarks |
| VM disks | QCOW2, VMDK, VHDX | Virtual capacity, format versions |
| Torrents | `.torrent` | Name, trackers, piece size, full file list |
| Terraform | `.tfstate` | Versions, resource counts by type |
| Certificates | PEM, DER, CRT, CER, P12/PFX | Subject, issuer, serial, validity (expiry flag) |
| Fonts | TTF, OTF, TTC, WOFF, WOFF2 | Family, style, glyphs, live specimen; WOFF header metadata |
| YAML | `.yaml`, `.yml` | Recognizes **Kubernetes manifests** (kind/name/images), **Docker Compose** (services), **GitHub Actions** (jobs/steps); top-level key summary + content |
| Source code | 30+ extensions | Content, language, line count, encoding detection |

DMG previews include the **partition list** read from the UDIF XML plist (blkx entries) alongside uncompressed size and version.

\* MKV/WebM are detected and labeled; AVFoundation cannot decode their streams, so track details are limited.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the layer design and [docs/ROADMAP.md](docs/ROADMAP.md) for everything planned (RAR/7z, Office, RAW, 3D/CAD, AI image metadata, …).

## Requirements

- macOS 13+
- Xcode 15+ (developed against Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & Run

```bash
scripts/test.sh        # run the core test suite (swift test)
scripts/build.sh       # generate the Xcode project and build everything
open build/Build/Products/Debug/OmniPreview.app
```

Launching the app once registers both Quick Look extensions with the system. Enable them under **System Settings → General → Login Items & Extensions → Quick Look**, then press Space on a supported file in Finder. To force Quick Look to pick up changes during development: `qlmanage -r && qlmanage -r cache`.

The app adds an **eye icon to the menu bar** with quick access to the preview tester, Settings (menu bar visibility, per-plugin enable/disable, cache clearing), the System Settings extension pane, and About. The main window doubles as a renderer test bench — drop any file onto it.

When the previewed file is an image, an **Annotate** toolbar button opens a markup editor with pen, line, rectangle, and text tools (color picker, stroke width, undo/clear). Annotations are stored in normalized coordinates and exported as PNG at the image's **native resolution** via Save PNG….

## IDE Setup (VS Code / SourceKit-LSP)

The Swift package lives in `Core/`, so [.vscode/settings.json](.vscode/settings.json) enables `swift.searchSubfoldersForPackages`. The app and extension sources belong to the Xcode project, which SourceKit-LSP can only understand through a build server:

```bash
brew install xcode-build-server
xcode-build-server config -project OmniPreview.xcodeproj -scheme OmniPreview
```

`buildServer.json` is machine-specific and gitignored. Without it you will see phantom "Cannot find type in scope" diagnostics in `App/` and the extension sources even though the build succeeds.

## Repository Layout

```
Core/                   Swift package: all preview logic (UI-independent) + SwiftUI views
  Sources/OmniPreviewCore/
    Detection/          Magic-byte and extension-based file detection
    Plugins/            Renderer protocol, registry, preview document model
    Renderers/          One plugin per file family
    Caching/            Pipeline with content-identity memory cache
  Sources/OmniPreviewUI/  Shared SwiftUI rendering of PreviewDocument
  Tests/                Unit tests with in-memory binary fixtures
App/                    Host app (registers extensions, drag-and-drop test bench)
PreviewExtension/       Quick Look preview extension (Space bar)
ThumbnailExtension/     Quick Look thumbnail extension (Finder icons)
project.yml             XcodeGen project definition (xcodeproj is generated, not committed)
```

## Security Model

- **Read-only, always.** No file is ever written, executed, or modified.
- **No decompression of archive entries.** Archive previews parse directory structures only, which makes zip bombs structurally harmless.
- **Bounds-checked binary parsing.** All parsers go through a checked reader; malformed input produces a clean error, never a crash or over-read.
- **Hard caps everywhere.** Header sizes, entry counts, string lengths, and read windows are all limited.
- **Sandboxed.** App and extensions run in the App Sandbox; extensions receive access only to the file being previewed.
