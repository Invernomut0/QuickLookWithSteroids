# OmniPreview

### The Missing Quick Look Upgrade for macOS

OmniPreview extends Quick Look with rich, read-only previews for modern developer, data, media, and infrastructure formats.

Current status:
- Native Swift architecture (Quick Look extensions + shared core)
- 29 renderer plugins
- Active Free/Pro licensing model
- Ongoing hardening of detection and metadata extraction (latest fixes include PEM/X.509 robustness, SQLite `.db` fallback, text/config edge cases, and improved media metadata resilience)

---

## Free vs Pro

OmniPreview is designed to be useful immediately in Free, while Pro unlocks advanced analysis and specialized format workflows.

### What Free includes

Free is built for everyday Finder usage, developers, and ops workflows.

- Archive browsing and metadata for common archive families
- Folder preview with Finder-style navigation
- Source code preview (plain text) with language detection
- Markdown source preview
- Image preview + metadata (including EXIF and AI metadata extraction where available)
- SQLite schema/table overview
- Certificates and PKCS#12 container identification
- YAML/INI/configuration insights
- GIS summaries (GeoJSON/KML/Shapefile)
- Torrent and Terraform state inspection
- CAD metadata summary
- Font metadata and specimen

### What Pro unlocks

Pro unlocks high-value renderers and richer visualization paths.

- Syntax highlighting with colors (50+ languages)
- Formatted Markdown rendering
- Office and publishing renderers (OOXML / OpenDocument / eBook advanced workflows)
- ML model deep inspection (GGUF, Safetensors, ONNX, NumPy/NPZ, PyTorch containers)
- Scientific data renderers (Parquet, HDF5, NetCDF, FITS, MATLAB, Arrow, DuckDB)
- Advanced 3D workflows (interactive model preview and richer metadata)
- Media deep metadata workflows (audio/video stream-level details)
- VM disk image renderers (QCOW2, VMDK, VHDX)
- Specialized package/asset families (JAR/WAR/APK/IPA, GPU texture formats)

---

## Detailed capability split

### OmniPreview Free

Perfect for developers, system administrators, and everyday macOS users.

Includes:

- Archive browsing (ZIP, TAR, Gzip, XZ, BZip2)
- Folder preview with Finder-style navigation
- Source code preview (50+ languages detected, plain text in Free)
- Markdown source preview
- Image previews and EXIF metadata
- AI image metadata extraction (ComfyUI, Automatic1111/Forge-style metadata)
- SQLite database inspection
- Certificates and PKCS#12 containers
- YAML, JSON, XML, TOML and configuration files
- GIS files (GeoJSON, KML, Shapefile)
- Torrents and Terraform state files
- CAD metadata (DXF, DWG, STEP, IGES)
- Font preview and specimen rendering

### OmniPreview Pro

Unlock advanced renderers designed for professional workflows.

#### Office & Publishing

- Microsoft Office documents
- OpenDocument files
- eBooks and digital publishing formats
- Cover extraction and embedded thumbnails

#### Machine Learning & AI

- GGUF large language models
- Safetensors checkpoints
- ONNX models
- NumPy arrays and NPZ archives
- PyTorch checkpoints

Inspect architectures, tensor layouts, metadata, quantization information, parameter counts and model internals directly from Finder.

#### Scientific Computing & Data Engineering

- Parquet
- HDF5
- NetCDF
- FITS
- MATLAB datasets
- Apache Arrow
- DuckDB

Quickly inspect metadata, schemas, dimensions and dataset structure without loading files into external tools.

#### 3D & Creative Assets

- Interactive SceneKit viewer
- STL
- OBJ
- PLY
- USDZ
- GLB
- glTF

Rotate, zoom and inspect geometry directly from Quick Look.

#### Media Production

- Audio metadata and codec inspection
- Video metadata and stream analysis
- Bitrate, frame rate and container information

#### Virtualization & Infrastructure

- QCOW2
- VMDK
- VHDX

Inspect virtual machine images without launching virtualization software.

#### Specialized Formats

- JAR
- WAR
- APK
- IPA
- GPU texture formats
- QOI
- DDS
- TGA
- KTX
- KTX2
- Radiance HDR

---

## Important transparency note (real-world behavior)

OmniPreview supports many formats directly, but for some Apple-native formats (especially common media/image/document types), macOS Quick Look may still choose the default system preview depending on UTI precedence and system policy.

Examples may include formats like `.mp4` on some machines/configurations.

This means:
- format support exists in OmniPreview codebase,
- but Finder may display the system-native preview for that file type in specific environments.

---

## Pricing

**OmniPreview Free** — Free forever

**OmniPreview Pro** — One-time purchase, lifetime license

No subscriptions. No recurring fees.

Unlock all current Pro renderers and receive future Pro renderer updates.

---

## Upgrade to Pro

Get access to all advanced renderers, future Pro plugins, and professional workflows.

After purchase, activate your license from:

**OmniPreview → Settings → License**
