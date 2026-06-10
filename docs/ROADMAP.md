# OmniPreview Roadmap

Phase 1 (shipped) is the plugin framework plus seven renderers. Everything
below follows the same recipe: one `PreviewRenderer` per family, UTIs
declared in `project.yml`, caps and read-only parsing enforced.

## Phase 2 — Archives & Documents (largely shipped)

- ~~TAR, TAR.GZ/TGZ, TAR.XZ listings~~ — shipped (bounded decompression).
- ~~JAR / APK / IPA, EPUB / CBZ, Office OOXML + ODF~~ — shipped.
- ~~ISO / DMG / DEB / RPM / CAB / MSI / PKG header metadata~~ — shipped.
- **7Z / RAR / CBR contents listing** — requires libarchive (vendored,
  per-renderer isolation); currently header metadata only.
- **ZIP64** support in `ZIPArchive`.
- **APK binary AndroidManifest decoding**; **WOFF→sfnt unwrapping** for
  live web-font specimens; **PKCS#12 prompting** for password-protected
  identities.

## Phase 3 — Media & Images

- ~~Image metadata panel (EXIF, lens data)~~ — shipped; histogram pending.
- ~~AI image metadata (A1111 / Forge / ComfyUI)~~ — shipped; ComfyUI node
  graph *visualization* pending.
- ~~Audio/video metadata~~ — shipped; waveform and timeline thumbnails pending.
- **JXL / QOI / DDS / TGA / EXR / KTX2** — per-format decoders.
- **Camera RAW (CR2/CR3/NEF/ARW/RAF/…)** — embedded JPEG + EXIF extraction.

## Phase 4 — Developer & Data (largely shipped)

- ~~PostgreSQL / MySQL dump summaries~~ — shipped (plain SQL + PGDMP).
- ~~PyTorch checkpoints, ONNX, NPZ~~ — shipped.
- ~~Terraform state~~ — shipped. Kubernetes YAML / Helm summaries pending.
- ~~VM disk images (VMDK / QCOW2 / VHDX)~~ — shipped.
- **Syntax highlighting** for source previews.
- **Parquet schema decoding** (Thrift) and **Arrow schema** (flatbuffers).
- **Docker/OCI image tarballs** — layer listing from manifest.json.
- **Git repositories** — branches, recent commits, contributors.
- **Home Assistant backups** — tar + manifest summary.
- **n8n / Node-RED workflows** — JSON graph summaries.

## Phase 5 — 3D, Scientific, Misc (largely shipped)

- ~~Interactive 3D viewer (STL/OBJ/PLY/USDZ)~~ — shipped (SceneKit/ModelIO).
  GLB/glTF interactive rendering pending (ModelIO has no glTF importer).
- ~~CAD metadata (STEP/DXF/IGES/DWG)~~ — shipped; geometry *rendering* pending.
- ~~GIS metadata (GeoJSON/KML/KMZ/Shapefile)~~ — shipped; MapKit visual
  preview pending.
- ~~Scientific headers (FITS/HDF5/NetCDF/NPY/NPZ/MAT)~~ — shipped.
- **Checksum panel** — MD5/SHA1/SHA256/BLAKE3 in the host app.

## Infrastructure

- Disk cache with SQLite index, versioning, automatic cleanup.
- Per-plugin enable/disable UI in the host app (App Group defaults).
- Fuzzing harness + 1000-file sample corpus for parser robustness.
- Performance test suite enforcing budgets (preview <150 ms, thumbnail <100 ms, <300 MB).
- Notarization + installer pipeline; App Store feasibility analysis.
- Public plugin SDK once the `PreviewRenderer` API stabilizes.
