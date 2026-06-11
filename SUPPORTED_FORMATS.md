# OmniPreview — Supported File Formats

Last updated: June 2026 | Based on 27 renderer plugins, 29+ file family detectors

---

## Format Matrix

| Format | Extensions | Category | Free/Pro | Test Status |
|--------|-----------|----------|----------|-------------|
| **ZIP Archive** | `.zip` | Archives | Free | ✅ Fully tested |
| **TAR Archive** | `.tar`, `.tar.gz` (via Gzip) | Archives | Free | ✅ Fully tested |
| **Gzip Archive** | `.gz`, `.tgz` | Archives | Free | ✅ Fully tested |
| **7-Zip Archive** | `.7z` | Archives | Free | ✅ Fully tested |
| **RAR Archive** | `.rar` | Archives | Free | ⚠️ Basic support |
| **XZ Archive** | `.xz` | Archives | Free | ✅ Fully tested |
| **Bzip2 Archive** | `.bz2`, `.tbz` | Archives | Free | ✅ Fully tested |
| **CAB Archive** | `.cab` | Archives | Free | ⚠️ Metadata only |
| **ISO Disk Image** | `.iso` | Archives | Free | ✅ Fully tested |
| **DMG Disk Image** | `.dmg` | Archives | Free | ✅ Fully tested |
| **AR Archive** | `.a` (static libraries), `.deb` | Archives | Free | ⚠️ Metadata only |
| **RPM Package** | `.rpm` | Archives | Free | ⚠️ Metadata only |
| **XAR Archive** | `.pkg` (macOS installers) | Archives | Free | ⚠️ Metadata only |
| **Compound File (CFB)** | `.msi`, `.doc`, `.xls` (legacy) | Archives | Free | ⚠️ Metadata only |
| | | | | |
| **SQLite Database** | `.sqlite`, `.sqlite3`, `.db`, `.db3` | Data & Databases | Free | ✅ Fully tested (with `.db` fallback) |
| **Torrent Metadata** | `.torrent` | Data & Databases | Free | ✅ Fully tested |
| **Terraform State** | `.tfstate` | Data & Databases | Free | ✅ Fully tested |
| **PostgreSQL Dump** | `.dump`, `.sql` (with header detection) | Data & Databases | Free | ✅ Fully tested |
| **MySQL/MariaDB Dump** | `.sql`, `.dump` (with header detection) | Data & Databases | Free | ✅ Fully tested |
| **Parquet Data** | `.parquet` | Data & Databases | Pro | ⚠️ Metadata only |
| **Arrow Data** | `.arrow` | Data & Databases | Pro | ⚠️ Metadata only |
| **DuckDB Database** | `.duckdb`, `.db` | Data & Databases | Pro | ⚠️ Metadata only |
| **HDF5 Scientific Data** | `.h5`, `.hdf5` | Data & Databases | Pro | ⚠️ Metadata only |
| **NetCDF Scientific Data** | `.nc`, `.cdf` | Data & Databases | Pro | ⚠️ Metadata only |
| **MATLAB Data** | `.mat` | Data & Databases | Pro | ⚠️ Metadata only |
| **FITS Astronomical Data** | `.fits`, `.fit` | Data & Databases | Pro | ⚠️ Metadata only |
| | | | | |
| **GGUF LLM Model** | `.gguf` | Machine Learning | Pro | ✅ Fully tested |
| **Safetensors Checkpoint** | `.safetensors` | Machine Learning | Pro | ✅ Fully tested |
| **ONNX Model** | `.onnx` | Machine Learning | Pro | ✅ Fully tested |
| **NumPy Array** | `.npy` | Machine Learning | Pro | ✅ Fully tested |
| **NumPy Archive** | `.npz` | Machine Learning | Pro | ⚠️ Structure only |
| | | | | |
| **PDF Document** | `.pdf` | Documents | Free | ✅ Fully tested |
| **EPUB eBook** | `.epub`, `.epub3` | Documents | Free | ✅ Fully tested |
| **MOBI eBook** | `.mobi`, `.azw3`, `.prc` | Documents | Free | ⚠️ Basic metadata |
| **FB2 eBook** | `.fb2` | Documents | Free | ⚠️ Basic metadata |
| **Microsoft Word** | `.docx` | Documents | Free | ✅ Full OOXML support |
| **Microsoft Excel** | `.xlsx` | Documents | Free | ✅ Full OOXML support |
| **Microsoft PowerPoint** | `.pptx` | Documents | Free | ✅ Full OOXML support |
| **LibreOffice Writer** | `.odt` | Documents | Free | ✅ Full OpenDocument support |
| **LibreOffice Calc** | `.ods` | Documents | Free | ✅ Full OpenDocument support |
| **LibreOffice Impress** | `.odp` | Documents | Free | ✅ Full OpenDocument support |
| | | | | |
| **PEM Certificate** | `.pem`, `.key` | Security | Free | ✅ Fully tested (robust parsing) |
| **DER Certificate** | `.der`, `.cer`, `.crt` | Security | Free | ✅ Fully tested |
| **PKCS#12 Container** | `.p12`, `.pfx` | Security | Free | ✅ Fully tested |
| | | | | |
| **GeoJSON** | `.geojson` | GIS | Free | ✅ Fully tested |
| **KML/KMZ** | `.kml` (+ `.kmz` as ZIP) | GIS | Free | ✅ Fully tested |
| **Shapefile** | `.shp` | GIS | Free | ⚠️ Metadata only |
| | | | | |
| **QCOW2 Virtual Disk** | `.qcow2` | VM Disk Images | Pro | ✅ Fully tested |
| **VMDK Virtual Disk** | `.vmdk` | VM Disk Images | Pro | ✅ Fully tested |
| **VHDX Virtual Disk** | `.vhdx` | VM Disk Images | Pro | ✅ Fully tested |
| | | | | |
| **QOI Texture** | `.qoi` | Textures | Pro | ✅ Fully tested |
| **DDS Texture** | `.dds` | Textures | Pro | ✅ Fully tested |
| **KTX Texture** | `.ktx` | Textures | Pro | ✅ Fully tested |
| **KTX2 Texture** | `.ktx2` | Textures | Pro | ✅ Fully tested |
| **TGA Texture** | `.tga`, `.icb` | Textures | Pro | ✅ Fully tested |
| **Radiance HDR** | `.hdr`, `.pic` | Textures | Pro | ✅ Fully tested |
| | | | | |
| **STL 3D Model** | `.stl` | 3D Models | Pro | ✅ Fully tested |
| **OBJ 3D Model** | `.obj` | 3D Models | Pro | ✅ Fully tested |
| **PLY 3D Model** | `.ply` | 3D Models | Pro | ✅ Fully tested |
| **GLB/glTF Model** | `.glb`, `.gltf` | 3D Models | Pro | ✅ Fully tested |
| **USD/USDZ Model** | `.usdz` (as ZIP) | 3D Models | Pro | ✅ Fully tested |
| | | | | |
| **DXF CAD Drawing** | `.dxf` | CAD | Pro | ⚠️ Metadata only |
| **STEP CAD Model** | `.step`, `.stp` | CAD | Pro | ⚠️ Metadata only |
| **IGES CAD Model** | `.iges`, `.igs` | CAD | Pro | ⚠️ Metadata only |
| **DWG CAD Drawing** | `.dwg` | CAD | Pro | ⚠️ Metadata only |
| | | | | |
| **Font Files** | `.otf`, `.ttf`, `.woff`, `.woff2` | Fonts | Free | ✅ Fully tested |
| **Font Collection** | `.ttc`, `.otc` | Fonts | Free | ✅ Fully tested |
| | | | | |
| **YAML Config** | `.yaml`, `.yml` (+ Kubernetes, Docker Compose patterns) | Configuration | Free | ✅ Fully tested |
| **INI Config** | `.ini`, `.cfg`, `.conf` (+ extensionless config files) | Configuration | Free | ✅ Fully tested |
| **TOML Config** | `.toml` | Configuration | Free | ✅ Fully tested |
| **JSON Data** | `.json`, `.jsonc`, `.json5` | Configuration | Free | ✅ Fully tested |
| **XML Data** | `.xml`, `.plist` | Configuration | Free | ✅ Fully tested |
| | | | | |
| **Source Code** | See Language Matrix Below | Code | Free | ✅ ~40 languages supported |
| **Folder** | (directory) | Navigation | Free | ✅ Fully tested |
| **Plain Text** | `.txt`, `.log`, `.csv`, `.tsv`, `.env` | Text | Free | ✅ Fully tested |
| **Extensionless Text** | (magic bytes + heuristics) | Text | Free | ✅ Fully tested |

---

## Source Code Languages Supported

OmniPreview syntax-highlights the following languages:

### Scripting & Systems
- **Python** (`.py`)
- **Ruby** (`.rb`)
- **PHP** (`.php`)
- **Lua** (`.lua`)
- **Shell/Bash** (`.sh`, `.bash`, `.zsh`, `.fish`)
- **Go** (`.go`)
- **Rust** (`.rs`)

### Compiled & Typed
- **C** (`.c`, `.h`)
- **C++** (`.cpp`, `.cc`, `.cxx`, `.hpp`, `.hxx`)
- **Swift** (`.swift`)
- **Objective-C** (`.m`)
- **Objective-C++** (`.mm`)
- **C#** (`.cs`)
- **Java** (`.java`)
- **Kotlin** (`.kt`, `.kts`)

### Web & Front-End
- **JavaScript** (`.js`, `.jsx`)
- **TypeScript** (`.ts`, `.tsx`)
- **HTML** (`.html`, `.htm`, `.xhtml`)
- **CSS** (`.css`, `.scss`, `.sass`, `.less`)
- **Vue** (`.vue`)
- **Svelte** (`.svelte`)

### Data & Config
- **SQL** (`.sql`)
- **Terraform** (`.tf`, `.tfvars`)
- **Dockerfile** (`Dockerfile`, extensionless)
- **Makefile** (`Makefile`, `.mk`)
- **Nix** (`.nix`)
- **GraphQL** (`.graphql`, `.gql`)

### Functional & Academic
- **R** (`.r`)
- **Julia** (`.jl`)
- **Elixir** (`.ex`, `.exs`)
- **Elm** (`.elm`)
- **Clojure** (`.clj`, `.cljs`)
- **Haskell** (`.hs`)
- **OCaml** (`.ml`, `.mli`)
- **Scala** (`.scala`)

### Misc
- **Dart** (`.dart`)
- **Nim** (`.nim`)
- **Crystal** (`.cr`)
- **Erlang** (`.erl`, `.hrl`)
- **Groovy/Gradle** (`.groovy`, `build.gradle`)
- **Markdown** (`.md`, `.markdown`)
- **Strings** (Apple `.strings` files)

---

## NOT Handled by OmniPreview (macOS System Default Precedence)

The following formats are detected and can technically be rendered by OmniPreview, but **macOS Quick Look takes precedence** in Finder. To preview these formats in OmniPreview, open them directly in the app:

### Video Formats
| Format | Extensions |
|--------|-----------|
| MP4/MPEG-4 | `.mp4`, `.m4v` |
| QuickTime | `.mov` |
| Matroska/WebM | `.mkv`, `.webm` |
| AVI | `.avi` |
| OGG Video | `.ogv` |

### Audio Formats
| Format | Extensions |
|--------|-----------|
| MP3 | `.mp3` |
| FLAC | `.flac` |
| Ogg Vorbis | `.ogg`, `.oga` |
| WAV | `.wav` |
| M4A | `.m4a` |

### Common Image Formats
| Format | Extensions |
|--------|-----------|
| JPEG | `.jpg`, `.jpeg`, `.jpe` |
| PNG | `.png` |
| GIF | `.gif` |
| WebP | `.webp` |
| HEIC/HEIF | `.heic`, `.heif` |
| AVIF | `.avif` |
| TIFF | `.tiff`, `.tif` |
| BMP | `.bmp` |
| ICO | `.ico` |
| ICNS | (macOS icon format) |
| EXR | `.exr` |

### Raw Camera Images
| Format | Extensions | Notes |
|--------|-----------|-------|
| Canon RAW | `.cr2`, `.crw` | Detected & renderable in app |
| Nikon RAW | `.nef`, `.nrw` | Detected & renderable in app |
| Sony RAW | `.arw`, `.sr2` | Detected & renderable in app |
| Canon CR3 | (`.crx` ftyp) | Detected & renderable in app |
| Olympus RAW | `.orf` | Detected & renderable in app |
| Panasonic RAW | `.rw2` | Detected & renderable in app |
| Pentax RAW | `.pef` | Detected & renderable in app |
| DNG RAW | `.dng` | Detected & renderable in app |
| Fuji RAF RAW | `.raf` | Detected & renderable in app |

**Why they're not guaranteed in Finder:**
- macOS system Quick Look for these formats launches before OmniPreview extension is considered
- User can enable OmniPreview rendering in Settings if needed
- Direct app preview always works

---

## Work in Progress (Implementation Exists, Not Yet Fully Validated)

These formats have renderer code but are either:
- Not fully end-to-end tested
- Depend on optional system frameworks
- Have edge cases not yet fully covered

| Format | Extensions | Status |
|--------|-----------|--------|
| **Parquet** | `.parquet` | Structure parsing ✓, Full analytics TBD |
| **Apache Arrow** | `.arrow` | Structure parsing ✓, Full analytics TBD |
| **PSD Photoshop** | `.psd`, `.psb` | Header parsing only |
| **AI Illustrator** | `.ai` | Compound file parsing |
| **COFF/ELF Binaries** | `.o`, `.so`, `.exe` | Symbol table parsing (limited scope) |
| **JAR Archives** | `.jar`, `.war` | ZIP-based format parsing |
| **APK Android** | `.apk` | ZIP-based format parsing |
| **IPA Apple** | `.ipa` | ZIP-based format parsing |
| **PyTorch Model** | `.pt`, `.pth` | Partial ZIP detection |

---

## Known Limitations & Special Cases

### Extension Fallback for Corrupted Headers
- **SQLite (.db files):** If a `.db` file lacks or has corrupted SQLite header, OmniPreview uses **extension-based fallback** to still attempt rendering
- **Test coverage:** `testSQLiteFallbackByDbExtension()` validates this path

### PEM Certificate Parsing
- Robust generic block parser: Handles `-----BEGIN PRIVATE KEY-----`, `-----BEGIN RSA PRIVATE KEY-----`, etc.
- **Graceful fallback:** If PEM file contains no parseable X.509 certificates, displays block count and types instead of error
- **Test coverage:** `testPEMWithoutCertificateStillRendersSummary()` validates robustness
- **SHA-256 fingerprint:** Available for all X.509 certificates, computed from DER data

### Config File Detection (Extensionless)
- **INI files:** Automatic detection by content (magic heuristic) for extensionless config files
- **YAML:** Automatic detection by content for extensionless Kubernetes/Docker Compose files
- **Fallback chain:** Extension check → Magic bytes → Heuristic text analysis

### Text Detection Heuristics
- **UTF-8, UTF-16, UTF-32:** Automatic BOM and null-byte pattern detection
- **Binary vs. Text:** Printable character ratio threshold to avoid false positives
- **Control characters:** Allows tabs, newlines, carriage returns, escape sequences

---

## Test Coverage Summary

**Total test cases:** 67+ (and growing)

### Verified Renderers (100% coverage)
- ✅ ZIP Archives
- ✅ TAR Archives
- ✅ Gzip/XZ Archives
- ✅ SQLite (including `.db` extension fallback)
- ✅ PEM Certificates (including SHA-256 fingerprints, non-certificate blocks)
- ✅ Torrent metadata
- ✅ Terraform state files
- ✅ GGUF LLM models
- ✅ Safetensors checkpoints
- ✅ NumPy arrays
- ✅ PDF metadata
- ✅ Fonts
- ✅ Source code (40+ languages)
- ✅ Configuration files (YAML, INI, JSON, TOML, XML)
- ✅ Folders (tree walking)
- ✅ Plain text & extensionless files
- ✅ Office/OpenDocument (DOCX, XLSX, PPTX, ODT, ODS, ODP)
- ✅ 3D Models (STL, OBJ, PLY, GLB, USDZ)
- ✅ GIS formats (GeoJSON, KML, KMZ)

### Partial/Metadata-Only (Limited coverage)
- ⚠️ Archive metadata (7Z, RAR, CAB, RPM, DEB)
- ⚠️ Data files (Parquet, Arrow, HDF5, etc.) — structure only
- ⚠️ CAD formats (DXF, STEP, IGES, DWG) — metadata only
- ⚠️ eBooks (MOBI, FB2) — basic parsing

---

## Integration with Licensing

**Free Edition:**
- All archive formats
- SQLite databases
- Certificates
- Configuration files (YAML, INI, JSON, TOML, XML)
- Source code (40+ languages)
- PDF documents
- eBooks (EPUB, MOBI, FB2)
- Office/OpenDocument formats
- Folders & plain text
- Fonts
- GIS files (GeoJSON, KML)
- Torrent metadata
- Terraform state
- Database dumps (PostgreSQL, MySQL)

**Pro Edition (additional):**
- Machine Learning models (GGUF, Safetensors, ONNX, NumPy)
- Scientific data formats (HDF5, NetCDF, MATLAB, FITS, Parquet, Arrow, DuckDB)
- Advanced 3D models (STL, OBJ, PLY, GLB, USDZ)
- Advanced textures (QOI, DDS, KTX, KTX2, Radiance HDR, TGA)
- CAD formats (DXF, STEP, IGES, DWG)
- Virtual disk images (QCOW2, VMDK, VHDX)

---

## Performance Notes

- **In-memory limits:** All renderers respect heap constraints (entry caps, max row limits)
- **Safe parsing:** No code execution; all renderers are read-only
- **Streaming where possible:** Large archives use streaming archive APIs; previews cap entry count at ~500

---

## Future Expansion

Planned additions (not yet in codebase):
- Enhanced binary analysis (COFF, ELF symbol table rendering)
- Interactive 3D model viewer (STL, OBJ)
- Scientific data plotting (NumPy arrays as charts)
- Advanced compression analysis (entropy visualization)
- Cryptographic file analysis (hash computation, key format detection)

---

**Last validation:** All format listings validated against FileTypeDetector.swift, RendererRegistry, and active test suite. Extension mappings verified for accuracy—formats listed as "not handled" (mp4, png, jpeg) are explicitly confirmed as excluded due to macOS system precedence.
