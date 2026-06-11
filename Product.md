# OmniPreview

### The Missing Quick Look Upgrade for macOS

OmniPreview extends Quick Look with read-only previews for developer, archive, data, and infrastructure formats.

Current status (June 2026):
- Native Swift architecture (Quick Look extensions + shared core)
- 29 renderer plugins in codebase
- Free/Pro licensing active
- Product messaging below is intentionally strict: only tested and currently reliable capabilities are listed as available; everything else is marked Work in Progress

---

## Free vs Pro

OmniPreview Free covers core daily workflows.
OmniPreview Pro unlocks advanced analysis features that are already test-covered.

> Validation policy used in this document:
> only capabilities covered by automated tests and considered stable are listed under Free/Pro.
> Non-tested or not consistently guaranteed behaviors are listed under **Work in Progress**.

### OmniPreview Free (tested and reliable)

Perfect for developers, system administrators, and everyday macOS users.

Includes:

- Archive browsing and metadata
	- ZIP, TAR, Gzip/TGZ
	- Header/metadata inspection for DMG and additional archive families
- Folder preview with Finder-style navigation
- Source code preview (plain text mode) with language detection and extensionless-text fallback
- Configuration and structured text workflows
	- INI/CFG (including extensionless config files)
	- YAML analysis (Kubernetes, Docker Compose, GitHub Actions patterns)
- SQLite inspection (including `.sqlite` and `.db` fallback handling)
- Certificates and identities
	- PEM summary (robust handling also for PEM without parseable cert)
	- DER/CER/CRT and PKCS#12 container identification
- Infrastructure and data summaries
	- Torrent metadata + file list
	- Terraform state summaries
	- GeoJSON/KML robustness paths

### OmniPreview Pro (tested and reliable)

Unlock advanced renderers designed for professional workflows.

#### Machine Learning & AI

- GGUF model inspection
- Safetensors checkpoint inspection
- NumPy `.npy` and `.npz` archive inspection

Inspect metadata, tensor/layout information, and structural model details directly from Finder.

#### Advanced technical formats

- QOI texture metadata
- QCOW2 virtual disk metadata
- STL model metadata path (with interactive viewer path in app/extension stack)
- PDF metadata/document info path

---

## Work in Progress

The following capabilities exist in code (fully or partially), but are currently not listed as guaranteed product promises because they are either not fully test-covered or not consistently selected by Finder in all environments.

### Not guaranteed in Finder due to macOS default-preview precedence

- Video formats (e.g. `.mp4`, `.mov`, `.m4v`, `.avi`, `.mkv`, `.webm`)
- Common image formats (e.g. `.png`, `.jpeg`, `.heic`, `.webp`, `.avif`, etc.)

These can be handled by OmniPreview internals, but Finder may still show the default macOS Quick Look preview.

### Implemented but not yet promoted as guaranteed

- Office and publishing stack (OOXML/OpenDocument/eBook advanced paths)
- ONNX model deep path
- Scientific datasets (Parquet, HDF5, NetCDF, FITS, MATLAB, Arrow, DuckDB)
- Additional VM disk formats beyond currently validated paths
- App/package families (JAR/WAR/APK/IPA/PyTorch package paths)
- Extended CAD/GIS/media matrices not fully covered by stable end-to-end validation
- Rich Pro rendering matrix for every declared source language

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
