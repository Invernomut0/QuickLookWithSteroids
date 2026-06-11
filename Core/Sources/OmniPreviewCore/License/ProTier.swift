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
        // ML & AI
        ("gguf",        "GGUF Models",              "cpu",                       "LLM model inspection: architecture, quantization, tensor count"),
        ("safetensors", "Safetensors Checkpoints",  "brain",                     "ML tensor inspection: dtype, shapes, parameter count"),
        ("onnx",        "ONNX Models",              "brain",                     "Neural network models: producer, IR version, domain metadata"),
        ("npy",         "NumPy Arrays & NPZ",       "square.grid.3x3",           "Scientific arrays: dtype, shape, element count; NPZ per-file table"),
        
        // Advanced renderers
        ("app-package", "App Packages",             "apps.iphone",               "JAR, APK, IPA metadata; PyTorch & NPZ storage inspection"),
        ("model3d",     "3D Models",                "cube",                      "Interactive viewer for STL, OBJ, PLY, GLB, USDZ; rotate & zoom"),
        ("texture",     "GPU Textures",             "photo.on.rectangle",        "QOI, DDS, TGA, KTX/KTX2, Radiance HDR dimensions & metadata"),
        ("data-file",   "Scientific Data",          "chart.bar.doc.horizontal",  "Parquet, Arrow, HDF5, NetCDF, MATLAB, FITS inspection"),
        ("disk-image",  "Virtual Disk Images",      "externaldrive",             "QCOW2, VMDK, VHDX metadata and capacity inspection"),
        
        // Documents & Media
        ("office",      "Office Documents",         "doc.text",                  "DOCX/XLSX/PPTX/ODT/ODS/ODP: title, author, stats, thumbnails"),
        ("ebook",       "eBook Formats",            "book.closed",               "EPUB with cover image, MOBI, AZW3, FB2, CBZ inspection"),
        ("media",       "Audio & Video",            "film",                      "Duration, codecs, resolution, bitrate, ID3 tags extraction"),
        
        // UI-level features
        ("syntax-highlighting", "Syntax Highlighting", "paintbrush.pointed.fill", "50+ languages with color-coded tokens: Swift, Python, JS, Rust, Go, etc."),
        ("markdown-rendering",  "Markdown Rendering",  "text.badge.checkmark",   "Full block rendering: headings, code blocks, tables, lists, blockquotes"),
        ("video-trim",          "Video Trim & Export", "scissors",                "Non-destructive trim with AVKit, export at full resolution"),
    ]

    public static func isPro(rendererID: String) -> Bool {
        proRendererIDs.contains(rendererID)
    }
}
