import XCTest
import Compression
@testable import OmniPreviewCore

final class FormatRendererTests: XCTestCase {
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        temporaryFiles = []
        super.tearDown()
    }

    private func detect(_ data: Data, name: String) throws -> DetectedFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        temporaryFiles.append(url)
        return try FileTypeDetector.detect(url: url)
    }

    private func keyValues(_ document: PreviewDocument, section: Int = 0) -> [KeyValueRow] {
        guard case .keyValues(_, let rows) = document.sections[section] else { return [] }
        return rows
    }

    // MARK: ZIP extraction

    func testZIPEntryExtractionStored() throws {
        let payload = Data("hello extraction".utf8)
        let data = FixtureBuilder.zip(entries: [("a/b.txt", payload)])
        let file = try detect(data, name: "x.zip")
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        let extracted = try archive.extract(archive.entry(at: "a/b.txt")!, maxBytes: 1024)
        XCTAssertEqual(extracted, payload)
    }

    func testZIPExtractionRespectsCap() throws {
        let payload = Data(repeating: 0x41, count: 4096)
        let data = FixtureBuilder.zip(entries: [("big.bin", payload)])
        let file = try detect(data, name: "x.zip")
        let archive = try ZIPArchive(url: file.url, fileSize: file.fileSize)
        XCTAssertThrowsError(try archive.extract(archive.entry(at: "big.bin")!, maxBytes: 1024))
        let prefix = try archive.extractPrefix(archive.entry(at: "big.bin")!, maxBytes: 1024)
        XCTAssertEqual(prefix.count, 1024)
    }

    // MARK: Compressed tar

    func testTGZListing() throws {
        let tar = FixtureBuilder.tar(entries: [
            ("src", Data(), true),
            ("src/main.swift", Data("print(1)".utf8), false),
        ])
        let gz = FixtureBuilder.gzipCompress(tar)
        let file = try detect(gz, name: "code.tar.gz")
        XCTAssertEqual(file.kind, .gzip)

        let document = try GzipRenderer().render(file)
        guard case .fileTree(_, let entries) = document.sections[1] else {
            return XCTFail("expected contents listing for a tarball")
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[1].path, "src/main.swift")
        XCTAssertEqual(entries[1].uncompressedSize, 8)
    }

    // MARK: Office / eBooks (ZIP-based)

    func testDOCXMetadata() throws {
        let core = """
        <?xml version="1.0"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Quarterly Report</dc:title><dc:creator>Lorenzo</dc:creator>
        </cp:coreProperties>
        """
        let app = """
        <?xml version="1.0"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
        <Pages>12</Pages><Words>3400</Words><Application>Microsoft Word</Application>
        </Properties>
        """
        let data = FixtureBuilder.zip(entries: [
            ("docProps/core.xml", Data(core.utf8)),
            ("docProps/app.xml", Data(app.utf8)),
            ("word/document.xml", Data("<w:document/>".utf8)),
        ])
        let file = try detect(data, name: "report.docx")

        let document = try OfficeRenderer().render(file)
        let docRows = keyValues(document, section: 0)
        XCTAssertEqual(docRows.first { $0.key == "Title" }?.value, "Quarterly Report")
        XCTAssertEqual(docRows.first { $0.key == "Author" }?.value, "Lorenzo")
        let stats = keyValues(document, section: 1)
        XCTAssertEqual(stats.first { $0.key == "Pages" }?.value, "12")
        XCTAssertEqual(stats.first { $0.key == "Words" }?.value, "3400")
    }

    func testEPUBMetadata() throws {
        let container = """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <metadata><dc:title>My Novel</dc:title><dc:creator>A. Writer</dc:creator><dc:language>en</dc:language></metadata>
        <manifest><item id="ch1" href="ch1.xhtml"/></manifest>
        <spine><itemref idref="ch1"/></spine>
        </package>
        """
        let data = FixtureBuilder.zip(entries: [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
        ])
        let file = try detect(data, name: "novel.epub")

        let document = try EbookRenderer().render(file)
        let rows = keyValues(document, section: 0)
        XCTAssertEqual(rows.first { $0.key == "Title" }?.value, "My Novel")
        XCTAssertEqual(rows.first { $0.key == "Author" }?.value, "A. Writer")
        XCTAssertEqual(rows.first { $0.key == "Spine items" }?.value, "1")
    }

    // MARK: Torrent

    func testTorrentParsing() throws {
        func bstr(_ s: String) -> String { "\(s.utf8.count):\(s)" }
        let bencoded = "d" + bstr("announce") + bstr("http://tracker/announce")
            + bstr("info") + "d"
            + bstr("files") + "l"
            + "d" + bstr("length") + "i500e" + bstr("path") + "l" + bstr("docs") + bstr("a.txt") + "ee"
            + "d" + bstr("length") + "i1500e" + bstr("path") + "l" + bstr("b.jpg") + "ee"
            + "e"
            + bstr("name") + bstr("MyStuff")
            + bstr("piece length") + "i16384e"
            + "ee"
        let file = try detect(Data(bencoded.utf8), name: "stuff.torrent")
        XCTAssertEqual(file.kind, .torrent)

        let document = try TorrentRenderer().render(file)
        let rows = keyValues(document, section: 0)
        XCTAssertEqual(rows.first { $0.key == "Name" }?.value, "MyStuff")
        XCTAssertEqual(rows.first { $0.key == "Total size" }?.value, Format.bytes(2000))
        guard case .fileTree(_, let entries) = document.sections[1] else {
            return XCTFail("expected file list")
        }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "docs/a.txt")
    }

    // MARK: Textures

    func testQOIHeader() throws {
        var data = Data("qoif".utf8)
        for value in [UInt32(640), UInt32(480)] {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [4, 0]) // RGBA, sRGB
        let file = try detect(data, name: "img.qoi")
        XCTAssertEqual(file.kind, .texture(format: "QOI"))

        let rows = keyValues(try TextureRenderer().render(file))
        XCTAssertEqual(rows.first { $0.key == "Dimensions" }?.value, "640 × 480")
        XCTAssertEqual(rows.first { $0.key == "Channels" }?.value, "RGBA")
    }

    // MARK: Disk images

    func testQCOW2Header() throws {
        var data = Data([0x51, 0x46, 0x49, 0xFB])
        for value in [UInt32(3)] { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        data.append(Data(count: 12)) // backing file offset (8) + size (4)
        withUnsafeBytes(of: UInt32(16).bigEndian) { data.append(contentsOf: $0) } // cluster bits
        withUnsafeBytes(of: UInt64(20 * 1024 * 1024 * 1024).bigEndian) { data.append(contentsOf: $0) }
        data.append(Data(count: 64))
        let file = try detect(data, name: "vm.qcow2")
        XCTAssertEqual(file.kind, .diskImage(format: "QCOW2"))

        let rows = keyValues(try DiskImageRenderer().render(file))
        XCTAssertEqual(rows.first { $0.key == "Virtual size" }?.value, Format.bytes(20 * 1024 * 1024 * 1024))
        XCTAssertEqual(rows.first { $0.key == "QCOW version" }?.value, "3")
    }

    // MARK: 3D

    func testBinarySTL() throws {
        var data = Data(count: 80)
        FixtureBuilder.appendLE(UInt32(2), to: &data)
        data.append(Data(count: 2 * 50))
        let file = try detect(data, name: "part.stl")
        XCTAssertEqual(file.kind, .model3D(format: "STL"))

        let document = try ThreeDRenderer().render(file)
        guard case .model3D = document.sections[0] else {
            return XCTFail("expected interactive 3D section")
        }
        let rows = keyValues(document, section: 1)
        XCTAssertEqual(rows.first { $0.key == "Triangles" }?.value, "2")
    }

    // MARK: FITS

    func testFITSHeader() throws {
        func card(_ text: String) -> String { text.padding(toLength: 80, withPad: " ", startingAt: 0) }
        let header = card("SIMPLE  =                    T") + card("BITPIX  =                   16")
            + card("NAXIS   =                    2") + card("NAXIS1  =                 1024")
            + card("NAXIS2  =                  768") + card("END")
        let file = try detect(Data(header.utf8) + Data(count: 2880), name: "image.fits")
        XCTAssertEqual(file.kind, .dataFile(format: "FITS"))

        let rows = keyValues(try DataFileRenderer().render(file))
        XCTAssertEqual(rows.first { $0.key == "NAXIS1" }?.value, "1024")
        XCTAssertEqual(rows.first { $0.key == "BITPIX" }?.value, "16")
    }

    // MARK: GeoJSON + Terraform state

    func testGeoJSON() throws {
        let geojson = """
        {"type": "FeatureCollection", "features": [
          {"type": "Feature", "geometry": {"type": "Point", "coordinates": [9.19, 45.46]}, "properties": {"name": "Milan"}},
          {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": []}, "properties": {"name": "Area"}}
        ]}
        """
        let file = try detect(Data(geojson.utf8), name: "places.geojson")
        XCTAssertEqual(file.kind, .geo(format: "GeoJSON"))

        let rows = keyValues(try GeoRenderer().render(file))
        XCTAssertEqual(rows.first { $0.key == "Features" }?.value, "2")
        XCTAssertEqual(rows.first { $0.key == "Point" }?.value, "1")
    }

    func testTerraformState() throws {
        let state = """
        {"version": 4, "terraform_version": "1.9.0", "serial": 7, "resources": [
          {"type": "aws_instance", "name": "a"}, {"type": "aws_instance", "name": "b"},
          {"type": "aws_s3_bucket", "name": "c"}
        ]}
        """
        let file = try detect(Data(state.utf8), name: "prod.tfstate")
        XCTAssertEqual(file.kind, .terraformState)

        let document = try DumpRenderer().render(file)
        let rows = keyValues(document, section: 0)
        XCTAssertEqual(rows.first { $0.key == "Resources" }?.value, "3")
        let types = keyValues(document, section: 1)
        XCTAssertEqual(types.first { $0.key == "aws_instance" }?.value, "2")
    }

    // MARK: NPZ

    func testNPZListsArrays() throws {
        let npy = FixtureBuilder.npy(descr: "<f8", shape: [10, 2])
        let data = FixtureBuilder.zip(entries: [("weights.npy", npy)])
        let file = try detect(data, name: "bundle.npz")

        let document = try AppPackageRenderer().render(file)
        guard case .table(_, _, let rows) = document.sections[1] else {
            return XCTFail("expected arrays table")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][0], "weights")
        XCTAssertEqual(rows[0][2], "10 × 2")
    }

    // MARK: Detection sweep for new formats

    func testNewFormatSignatures() {
        func kind(_ head: [UInt8], _ name: String) -> FileKind {
            FileTypeDetector.detectKind(head: Data(head), url: URL(fileURLWithPath: "/tmp/\(name)"))
        }
        XCTAssertEqual(kind(Array("BZh9".utf8), "a.bz2"), .bzip2)
        XCTAssertEqual(kind(Array("MSCF".utf8), "a.cab"), .cab)
        XCTAssertEqual(kind(Array("!<arch>\n".utf8), "lib.a"), .arArchive)
        XCTAssertEqual(kind([0xED, 0xAB, 0xEE, 0xDB], "p.rpm"), .rpmPackage)
        XCTAssertEqual(kind(Array("xar!".utf8), "i.pkg"), .xar)
        XCTAssertEqual(kind([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], "s.msi"), .compoundFile)
        XCTAssertEqual(kind(Array("PAR1".utf8), "t.parquet"), .dataFile(format: "Parquet"))
        XCTAssertEqual(kind(Array("ARROW1".utf8), "t.arrow"), .dataFile(format: "Arrow"))
        XCTAssertEqual(kind([0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A], "d.h5"), .dataFile(format: "HDF5"))
        XCTAssertEqual(kind(Array("MATLAB 5.0".utf8), "m.mat"), .dataFile(format: "MATLAB"))
        XCTAssertEqual(kind(Array("8BPS".utf8) + [0, 1], "a.psd"), .image(format: "PSD"))
        XCTAssertEqual(kind(Array("icns".utf8), "a.icns"), .image(format: "ICNS"))
        XCTAssertEqual(kind([0x76, 0x2F, 0x31, 0x01], "r.exr"), .image(format: "EXR"))
        XCTAssertEqual(kind([0xFF, 0x0A], "i.jxl"), .image(format: "JPEG XL"))
        XCTAssertEqual(kind(Array("FUJIFILMCCD-RAW".utf8), "p.raf"), .image(format: "Fuji RAF RAW"))
        XCTAssertEqual(kind([0x49, 0x49, 0x2A, 0x00], "p.cr2"), .image(format: "Canon CR2 RAW"))
        XCTAssertEqual(kind([0, 0, 0, 0x18] + Array("ftypcrx ".utf8), "p.cr3"), .image(format: "Canon CR3 RAW"))
        XCTAssertEqual(kind([0x1A, 0x45, 0xDF, 0xA3], "v.mkv"), .video(format: "Matroska"))
        XCTAssertEqual(kind(Array("qoif".utf8), "t.qoi"), .texture(format: "QOI"))
        XCTAssertEqual(kind(Array("DDS ".utf8), "t.dds"), .texture(format: "DDS"))
        XCTAssertEqual(kind(Array("glTF".utf8), "m.glb"), .model3D(format: "GLB"))
        XCTAssertEqual(kind(Array("ISO-10303-21".utf8), "m.step"), .cad(format: "STEP"))
        XCTAssertEqual(kind(Array("AC1032".utf8), "d.dwg"), .cad(format: "DWG"))
        XCTAssertEqual(kind([0x00, 0x00, 0x27, 0x0A], "m.shp"), .geo(format: "Shapefile"))
        XCTAssertEqual(kind([0x51, 0x46, 0x49, 0xFB], "v.qcow2"), .diskImage(format: "QCOW2"))
        XCTAssertEqual(kind(Array("KDMV".utf8), "v.vmdk"), .diskImage(format: "VMDK"))
        XCTAssertEqual(kind(Array("PGDMP".utf8), "d.dump"), .sqlDump(format: "PostgreSQL (custom format)"))
        XCTAssertEqual(kind([0x30, 0x82], "id.p12"), .pkcs12)
    }

    func testEverySupportedKindHasARenderer() {
        let kinds: [FileKind] = [
            .zip, .tar, .gzip, .sevenZip, .rar, .xz, .bzip2, .cab, .iso, .dmg,
            .arArchive, .rpmPackage, .xar, .compoundFile, .sqlite, .torrent,
            .dataFile(format: "Parquet"), .terraformState, .sqlDump(format: "MySQL"),
            .safetensors, .gguf, .onnx, .npy, .pdf,
            .image(format: "PNG"), .texture(format: "QOI"),
            .audio(format: "MP3"), .video(format: "MP4"), .mobi, .fb2,
            .model3D(format: "STL"), .cad(format: "DXF"),
            .geo(format: "GeoJSON"), .diskImage(format: "QCOW2"),
            .pemCertificate, .derCertificate, .pkcs12, .font,
            .sourceCode(language: "Swift"),
        ]
        for kind in kinds {
            let file = DetectedFile(url: URL(fileURLWithPath: "/tmp/x"), kind: kind, fileSize: 0)
            XCTAssertNotNil(RendererRegistry.renderer(for: file), "no renderer for \(kind)")
        }
    }
}
