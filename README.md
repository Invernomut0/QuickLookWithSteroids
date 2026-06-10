# OmniPreview

A native macOS Quick Look extension framework that brings rich previews to file types macOS does not support — archives, ML model files, databases, certificates, fonts, and more. Pure Swift, sandboxed, no Electron, no WebViews.

## Status

**Phase 1+ — working foundation.** The core framework, the host app, both Quick Look extensions, and thirteen renderer plugins are implemented and tested:

| Renderer | Formats | Preview |
|---|---|---|
| ZIP Archive | `.zip`, `.jar`, … | File tree, sizes, compression ratio — without extracting anything |
| TAR Archive | `.tar` | File tree with sizes and dates (streaming, GNU long names supported) |
| Gzip | `.gz`, `.tgz` | Original filename, modification date, producing OS |
| SQLite | `.sqlite`, `.db`, `.sqlite3` | Schema, tables, column and row counts (read-only, `immutable=1`) |
| Safetensors | `.safetensors` | Tensor list, dtypes, shapes, parameter count, embedded metadata |
| GGUF | `.gguf` | Architecture, quantization metadata, tensor count |
| NumPy | `.npy` | dtype, shape, element count, memory order |
| PDF | `.pdf` | Page count/size, document info, bookmarks, encryption status |
| Images | PNG, JPEG, GIF, TIFF, WebP, HEIC, AVIF | Picture, dimensions, color info, EXIF camera data — plus **AI generation metadata** (Automatic1111/Forge parameters, ComfyUI prompt/model/LoRA/sampler/seed) from PNG chunks |
| Audio/Video | MP3, FLAC, WAV, Ogg, M4A, MP4, MOV, AVI | Duration, codecs, resolution, frame rate, bitrate, tags |
| Certificates | `.pem`, `.crt`, `.cer`, `.der` | Subject, issuer, serial, validity (with expiry flag) |
| Fonts | `.ttf`, `.otf`, `.ttc` | Family, style, glyph count, live specimen |
| Source code | 30+ extensions | Content, language, line count, encoding detection |

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
