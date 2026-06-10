import Foundation

/// File families OmniPreview understands. Detection is signature-first
/// (magic bytes), extension-second — never extension-only for binary formats.
public enum FileKind: Equatable, Sendable {
    // Archives
    case zip
    case tar
    case gzip
    case sevenZip
    case rar
    case xz
    case bzip2
    case cab
    case iso
    case dmg
    case arArchive       // Unix ar: .a static libraries, .deb packages
    case rpmPackage
    case xar             // macOS .pkg installers
    case compoundFile    // CFB: .msi, legacy .doc/.xls/.ppt

    // Data & databases
    case sqlite
    case torrent
    case dataFile(format: String)   // Parquet, Arrow, DuckDB, HDF5, NetCDF, MAT, FITS
    case terraformState
    case sqlDump(format: String)    // PostgreSQL / MySQL dump

    // Machine learning
    case safetensors
    case gguf
    case onnx
    case npy

    // Documents & media
    case pdf
    case image(format: String)
    case texture(format: String)    // QOI, DDS, TGA, KTX, KTX2, HDR
    case audio(format: String)
    case video(format: String)
    case mobi                        // MOBI / AZW3 (PalmDB)
    case fb2

    // 3D & CAD
    case model3D(format: String)    // STL, OBJ, PLY, GLB, GLTF
    case cad(format: String)        // DXF, STEP, IGES, DWG

    // GIS
    case geo(format: String)        // GeoJSON, KML, Shapefile

    // Virtual machine disk images
    case diskImage(format: String)  // QCOW2, VMDK, VHDX

    // Security
    case pemCertificate
    case derCertificate
    case pkcs12

    // Misc
    case font
    case sourceCode(language: String)
    case unknown
}

public struct DetectedFile: Sendable {
    public let url: URL
    public let kind: FileKind
    public let fileSize: UInt64

    public init(url: URL, kind: FileKind, fileSize: UInt64) {
        self.url = url
        self.kind = kind
        self.fileSize = fileSize
    }

    public var pathExtension: String { url.pathExtension.lowercased() }
}
