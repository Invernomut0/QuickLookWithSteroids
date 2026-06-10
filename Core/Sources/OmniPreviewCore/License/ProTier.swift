import Foundation

/// Defines which renderer plugins require an OmniPreview Pro license.
///
/// Free tier covers every developer/power-user essential: archives, source
/// code with syntax highlighting, Markdown, SQLite, PDF, images, folders,
/// certificates, fonts, and GIS.
///
/// Pro tier adds the high-value analysis formats targeted at ML engineers,
/// data scientists, 3D artists, and creative professionals.
public enum ProTier {

    /// Renderer IDs that require a valid Pro license.
    /// Must match the `id` static property on each renderer.
    public static let proRendererIDs: Set<String> = [
        "safetensors",   // Safetensors model inspection
        "gguf",          // GGUF / LLM model inspection
        "onnx",          // ONNX model inspection
        "npy",           // NumPy arrays and NPZ archives
        "app-package",   // JAR, APK, IPA, NPZ, PyTorch checkpoints
        "model3d",       // Interactive 3D viewer (STL, OBJ, GLB, USDZ…)
        "office",        // DOCX, XLSX, PPTX, ODT, ODS, ODP
        "ebook",         // EPUB (with cover), MOBI, AZW3, FB2, CBZ
        "media",         // Audio & video (duration, codecs, tags)
        "data-file",     // Parquet, Arrow, HDF5, NetCDF, MATLAB, FITS
        "disk-image",    // QCOW2, VMDK, VHDX
        "texture",       // QOI, DDS, TGA, KTX, KTX2, Radiance HDR
    ]

    /// Human-readable names shown in the "Pro Features" list in Settings.
    public static let proFeatureDescriptions: [(id: String, name: String, icon: String, detail: String)] = [
        ("gguf",        "GGUF Models",         "cpu",                  "Architecture, quantization, tensor count, all metadata"),
        ("safetensors", "Safetensors Models",  "brain",               "Tensor list, dtypes, shapes, parameter count"),
        ("onnx",        "ONNX Models",         "brain",               "Producer, IR version, domain"),
        ("npy",         "NumPy / NPZ",         "square.grid.3x3",     "Array dtype, shape, element count; per-array table for NPZ"),
        ("app-package", "App Packages",        "apps.iphone",         "JAR/APK/IPA metadata; PyTorch checkpoint storage stats"),
        ("model3d",     "3D Models",           "cube",                "Interactive SceneKit viewer — rotate, zoom, orbit"),
        ("office",      "Office Documents",    "doc.text",            "DOCX / XLSX / PPTX / ODT — title, author, stats, thumbnail"),
        ("ebook",       "eBooks",              "book.closed",         "EPUB with cover image, MOBI, AZW3, FB2, CBZ"),
        ("media",       "Audio & Video",       "film",                "Duration, codecs, resolution, bitrate, ID3 tags"),
        ("data-file",   "Scientific Data",     "chart.bar.doc.horizontal", "Parquet, HDF5, NetCDF dimensions, FITS header, MATLAB"),
        ("disk-image",  "VM Disk Images",      "externaldrive",       "QCOW2 / VMDK virtual capacity, VHDX creator"),
        ("texture",     "GPU Textures",        "photo.on.rectangle",  "QOI, DDS, TGA, KTX/KTX2, Radiance HDR dimensions & format"),
    ]

    public static func isPro(rendererID: String) -> Bool {
        proRendererIDs.contains(rendererID)
    }
}
