import XCTest
import SQLite3
@testable import OmniPreviewCore

final class RendererTests: XCTestCase {
    private var temporaryFiles: [URL] = []

    override func tearDown() {
        for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
        temporaryFiles = []
        super.tearDown()
    }

    private func detect(_ data: Data, ext: String) throws -> DetectedFile {
        let url = try FixtureBuilder.write(data, extension: ext)
        temporaryFiles.append(url)
        return try FileTypeDetector.detect(url: url)
    }

    // MARK: ZIP

    func testZIPListing() throws {
        let data = FixtureBuilder.zip(entries: [
            ("docs/", Data()),
            ("docs/readme.txt", Data("hello world".utf8)),
            ("image.png", Data(repeating: 0xAB, count: 1024)),
        ])
        let file = try detect(data, ext: "zip")
        XCTAssertEqual(file.kind, .zip)

        let document = try ZIPRenderer().render(file)
        // ZIP now uses a folderTree section (unified Finder-style view).
        guard case .folderTree(let nodes) = document.sections[1] else {
            return XCTFail("expected folderTree section")
        }
        // Tree is sorted: folders first, then files.
        XCTAssertEqual(nodes.first?.name, "docs")
        XCTAssertTrue(nodes.first!.isDirectory)
        XCTAssertEqual(nodes.first!.children?.first?.name, "readme.txt")
        XCTAssertEqual(nodes.first!.children?.first?.size, 11)
        XCTAssertEqual(nodes.last?.name, "image.png")
        XCTAssertEqual(nodes.last?.size, 1024)
    }

    func testZIPRejectsGarbage() throws {
        let file = try detect(Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 100), ext: "zip")
        XCTAssertThrowsError(try ZIPRenderer().render(file))
    }

    // MARK: Safetensors

    func testSafetensorsHeader() throws {
        let data = FixtureBuilder.safetensors(
            header: [
                "__metadata__": ["format": "pt"],
                "model.weight": ["dtype": "F32", "shape": [4, 8], "data_offsets": [0, 128]],
            ],
            dataBytes: 128
        )
        let file = try detect(data, ext: "safetensors")
        XCTAssertEqual(file.kind, .safetensors)

        let document = try SafetensorsRenderer().render(file)
        guard case .keyValues(_, let summary) = document.sections[0] else {
            return XCTFail("expected summary section")
        }
        XCTAssertEqual(summary.first { $0.key == "Tensors" }?.value, "1")
        XCTAssertEqual(summary.first { $0.key == "Parameters" }?.value, "32")
    }

    func testSafetensorsRejectsImplausibleHeaderLength() throws {
        var data = Data()
        FixtureBuilder.appendLE(UInt64.max, to: &data)
        data.append(UInt8(ascii: "{"))
        data.append(Data(count: 64))
        let file = try detect(data, ext: "safetensors")
        XCTAssertThrowsError(try SafetensorsRenderer().render(file))
    }

    // MARK: GGUF

    func testGGUFMetadata() throws {
        let data = FixtureBuilder.gguf(
            metadata: [
                ("general.architecture", "llama"),
                ("general.name", "Test Model"),
            ],
            tensorCount: 291
        )
        let file = try detect(data, ext: "gguf")
        XCTAssertEqual(file.kind, .gguf)

        let document = try GGUFRenderer().render(file)
        guard case .keyValues(_, let summary) = document.sections[0] else {
            return XCTFail("expected summary section")
        }
        XCTAssertEqual(summary.first { $0.key == "Architecture" }?.value, "llama")
        XCTAssertEqual(summary.first { $0.key == "Tensors" }?.value, "291")

        guard case .keyValues(_, let metadata) = document.sections[1] else {
            return XCTFail("expected metadata section")
        }
        XCTAssertEqual(metadata.first { $0.key == "general.name" }?.value, "Test Model")
    }

    func testGGUFRejectsBadVersion() throws {
        var data = Data(Array("GGUF".utf8))
        FixtureBuilder.appendLE(UInt32(99), to: &data)
        FixtureBuilder.appendLE(UInt64(0), to: &data)
        FixtureBuilder.appendLE(UInt64(0), to: &data)
        let file = try detect(data, ext: "gguf")
        XCTAssertThrowsError(try GGUFRenderer().render(file))
    }

    // MARK: SQLite

    func testSQLiteSchema() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).sqlite")
        temporaryFiles.append(url)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO users (name) VALUES ('a'), ('b'), ('c')", nil, nil, nil)
        sqlite3_close_v2(db)

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .sqlite)

        let document = try SQLiteRenderer().render(file)
        guard case .table(_, _, let rows) = document.sections[1] else {
            return XCTFail("expected tables section")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], ["users", "2", "3"])
    }

    func testSQLiteSchemaWithDbExtension() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).db")
        temporaryFiles.append(url)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE items (id INTEGER PRIMARY KEY, value TEXT)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO items (value) VALUES ('x')", nil, nil, nil)
        sqlite3_close_v2(db)

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .sqlite)

        let document = try SQLiteRenderer().render(file)
        guard case .table(_, _, let rows) = document.sections[1] else {
            return XCTFail("expected tables section")
        }
        XCTAssertEqual(rows.first?[0], "items")
    }

    func testPEMWithoutCertificateStillRendersSummary() throws {
        let pem = """
        -----BEGIN PRIVATE KEY-----
        QUJDRA==
        -----END PRIVATE KEY-----
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).pem")
        try Data(pem.utf8).write(to: url)
        temporaryFiles.append(url)

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .pemCertificate)

        let document = try CertificateRenderer().render(file)
        XCTAssertEqual(document.subtitle, "PEM Container")
        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected summary section")
        }
        XCTAssertEqual(rows.first { $0.key == "PEM blocks" }?.value, "1")
        XCTAssertNotNil(rows.first(where: { $0.key == "Note" }))
    }

    // MARK: Source code

    func testSourceCodeMetadata() throws {
        let file = try detect(Data("line one\nline two\nline three".utf8), ext: "swift")
        let document = try SourceCodeRenderer().render(file)
        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected metadata section")
        }
        XCTAssertEqual(rows.first { $0.key == "Lines" }?.value, "3")
        XCTAssertEqual(rows.first { $0.key == "Language" }?.value, "Swift")
        XCTAssertEqual(rows.first { $0.key == "Encoding" }?.value, "UTF-8")
    }

    // MARK: Pipeline

    func testPipelineCachesByContentIdentity() async throws {
        let data = FixtureBuilder.zip(entries: [("a.txt", Data("x".utf8))])
        let url = try FixtureBuilder.write(data, extension: "zip")
        temporaryFiles.append(url)

        let pipeline = PreviewPipeline()
        let first = try await pipeline.document(for: url)
        let second = try await pipeline.document(for: url)
        XCTAssertEqual(first.title, second.title)
    }

    func testPipelineRendersEmptyConfigAndExtensionlessFiles() async throws {
        let cases: [(String, String)] = [
            ("empty-ini", "ini"),
            ("empty-cfg", "cfg"),
            ("empty-toml", "toml"),
            ("empty-extensionless", ""),
        ]

        let pipeline = PreviewPipeline()
        for (name, ext) in cases {
            var url = FileManager.default.temporaryDirectory
                .appendingPathComponent("omnipreview-test-\(UUID().uuidString)-\(name)")
            if !ext.isEmpty {
                url.appendPathExtension(ext)
            }
            try Data().write(to: url)
            temporaryFiles.append(url)

            let document = try await pipeline.document(for: url)
            XCTAssertFalse(document.sections.isEmpty, "expected at least one section for \(name)")
        }
    }

    func testPipelineHandlesMalformedKMLWithoutThrowing() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString)-broken")
            .appendingPathExtension("kml")
        try Data("this is not xml".utf8).write(to: url)
        temporaryFiles.append(url)

        let document = try await PreviewPipeline().document(for: url)
        XCTAssertEqual(document.iconSystemName, "map")
        XCTAssertFalse(document.sections.isEmpty)

        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected keyValues summary section")
        }
        XCTAssertNotNil(rows.first(where: { $0.key == "Note" }))
    }

    // MARK: Unknown-file text fallback

    func testUnknownTextFileIsRenderedAsPlainText() throws {
        let text = "Hello from an unknown extension\nline two\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).xyzzy")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .sourceCode(language: "Plain Text"))

        let renderer = RendererRegistry.renderer(for: file)
        XCTAssertNotNil(renderer, "unknown text file should fall through to SourceCodeRenderer")
        XCTAssertEqual(type(of: renderer!).id, SourceCodeRenderer.id)

        let document = try SourceCodeRenderer().render(file)
        XCTAssertEqual(document.subtitle, "Plain Text")
        guard case .text(let content, let language) = document.sections[1] else {
            return XCTFail("expected text section")
        }
        XCTAssertEqual(language, "Plain Text")
        XCTAssertTrue(content.contains("Hello from an unknown extension"))
    }

    func testUnknownBinaryFileIsNotRendered() throws {
        let binary = Data([0x00, 0xFF, 0x00, 0xAB, 0xCD, 0x00, 0x01, 0x02, 0x00, 0x03])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).xyzzy")
        try binary.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .unknown)
        XCTAssertNil(RendererRegistry.renderer(for: file), "binary unknown file should have no renderer")
    }

    func testRegistryRespectsDisabledRenderers() {
        let file = DetectedFile(url: URL(fileURLWithPath: "/tmp/x.zip"), kind: .zip, fileSize: 0)
        XCTAssertNotNil(RendererRegistry.renderer(for: file))

        RendererSettings.setEnabled(id: ZIPRenderer.id, false)
        defer { RendererSettings.setEnabled(id: ZIPRenderer.id, true) }
        XCTAssertNil(RendererRegistry.renderer(for: file))
    }

    func testRegistryFindsRendererForEachSupportedKind() {
        let kinds: [FileKind] = [.zip, .sqlite, .safetensors, .gguf, .pemCertificate, .font, .sourceCode(language: "Swift")]
        for kind in kinds {
            let file = DetectedFile(url: URL(fileURLWithPath: "/tmp/x"), kind: kind, fileSize: 0)
            XCTAssertNotNil(RendererRegistry.renderer(for: file), "no renderer for \(kind)")
        }
    }
}
