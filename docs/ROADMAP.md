# OmniPreview Roadmap

Phase 1 (shipped) is the plugin framework plus seven renderers. Everything
below follows the same recipe: one `PreviewRenderer` per family, UTIs
declared in `project.yml`, caps and read-only parsing enforced.

## Phase 2 — Archives & Documents

- ~~TAR~~ — shipped. **TAR.GZ contents listing** still needs bounded gzip
  inflation (`Compression.framework` raw inflate after manual header parse);
  the gzip renderer currently shows header metadata only.
- **7Z, RAR, XZ, BZ2, CAB, ISO, DEB, RPM** — requires libarchive (vendored,
  per-renderer isolation). Detection signatures already in place.
- **ZIP64** support in the existing ZIP renderer.
- **JAR / APK / IPA** — ZIP renderer + manifest extraction.
- **eBooks (EPUB / CBZ)** — EPUB is ZIP + OPF metadata; CBZ is ZIP + covers.
- **PDF enhanced metadata** — PDFKit: bookmarks, page count, encryption info.
- **Office (DOCX/XLSX/PPTX)** — ZIP + XML; first-page/sheet/slide summaries.

## Phase 3 — Media & Images

- ~~Image metadata panel (EXIF, lens data)~~ — shipped; histogram pending.
- ~~AI image metadata (A1111 / Forge / ComfyUI)~~ — shipped; ComfyUI node
  graph *visualization* pending.
- ~~Audio/video metadata~~ — shipped; waveform and timeline thumbnails pending.
- **JXL / QOI / DDS / TGA / EXR / KTX2** — per-format decoders.
- **Camera RAW (CR2/CR3/NEF/ARW/RAF/…)** — embedded JPEG + EXIF extraction.

## Phase 4 — Developer & Data

- **Syntax highlighting** for source previews.
- **PostgreSQL / MySQL dumps** — header + schema summary.
- **Parquet / Arrow / DuckDB** — schema and row counts.
- **PyTorch checkpoints, ONNX** — same approach as safetensors/GGUF.
- **Docker/OCI image tarballs** — layer listing, manifest metadata.
- **Terraform state, Kubernetes YAML, Helm** — structured summaries.
- **Git repositories** — branches, recent commits, contributors.
- **VM disk images (VMDK / QCOW2 / VHDX)** — header metadata.
- **Home Assistant backups** — tar + manifest summary.
- **n8n / Node-RED workflows** — JSON graph summaries.

## Phase 5 — 3D, Scientific, Misc

- **3D viewer (STL/OBJ/GLTF/GLB/USDZ)** — SceneKit/Metal interactive preview.
- **CAD (STEP/DXF)** — geometry preview.
- **GIS (GeoJSON/KML/Shapefile)** — MapKit preview.
- **Scientific (FITS/HDF5/NetCDF/NPY/NPZ/MAT)** — header + array metadata.
- **Checksum panel** — MD5/SHA1/SHA256/BLAKE3 in the host app.

## Infrastructure

- Disk cache with SQLite index, versioning, automatic cleanup.
- Per-plugin enable/disable UI in the host app (App Group defaults).
- Fuzzing harness + 1000-file sample corpus for parser robustness.
- Performance test suite enforcing budgets (preview <150 ms, thumbnail <100 ms, <300 MB).
- Notarization + installer pipeline; App Store feasibility analysis.
- Public plugin SDK once the `PreviewRenderer` API stabilizes.
