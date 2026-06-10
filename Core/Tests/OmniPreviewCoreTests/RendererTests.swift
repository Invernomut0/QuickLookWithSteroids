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
        guard case .fileTree(_, let entries) = document.sections[1] else {
            return XCTFail("expected file tree section")
        }
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].path, "docs/")
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].uncompressedSize, 11)
        XCTAssertEqual(entries[2].uncompressedSize, 1024)
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
