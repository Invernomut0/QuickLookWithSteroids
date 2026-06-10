import XCTest
import CoreGraphics
import ImageIO
@testable import OmniPreviewCore

final class NewRendererTests: XCTestCase {
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

    // MARK: Regression — fixed defects

    func testGGUFHostileArrayCountDoesNotCrash() throws {
        // Array with count UInt64.max used to trap on Int conversion;
        // it must now degrade to a truncated-metadata document.
        var data = Data(Array("GGUF".utf8))
        FixtureBuilder.appendLE(UInt32(3), to: &data)
        FixtureBuilder.appendLE(UInt64(0), to: &data) // tensors
        FixtureBuilder.appendLE(UInt64(1), to: &data) // kv count
        FixtureBuilder.appendLE(UInt64(1), to: &data) // key length
        data.append(UInt8(ascii: "a"))
        FixtureBuilder.appendLE(UInt32(9), to: &data) // type: array
        FixtureBuilder.appendLE(UInt32(4), to: &data) // element type: uint32
        FixtureBuilder.appendLE(UInt64.max, to: &data) // hostile count

        let file = try detect(data, ext: "gguf")
        let document = try GGUFRenderer().render(file)
        guard case .keyValues(_, let summary) = document.sections[0] else {
            return XCTFail("expected summary")
        }
        XCTAssertTrue(summary.contains { $0.value.contains("partially shown") })
    }

    func testSourceCodeLatin1Detection() throws {
        let latin1 = Data([0x63, 0x61, 0x66, 0x66, 0xE8]) // "caffè" in ISO Latin 1
        let file = try detect(latin1, ext: "py")
        let document = try SourceCodeRenderer().render(file)
        guard case .text(let content, _) = document.sections[1] else {
            return XCTFail("expected text section")
        }
        XCTAssertTrue(content.hasPrefix("caff"))
        XCTAssertFalse(content.isEmpty)
    }

    // MARK: TAR

    func testTARListing() throws {
        let data = FixtureBuilder.tar(entries: [
            ("docs", Data(), true),
            ("docs/readme.txt", Data("hello".utf8), false),
            ("big.bin", Data(repeating: 0, count: 1500), false),
        ])
        let file = try detect(data, ext: "tar")
        XCTAssertEqual(file.kind, .tar)

        let document = try TARRenderer().render(file)
        guard case .fileTree(_, let entries) = document.sections[1] else {
            return XCTFail("expected file tree")
        }
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].path, "docs/readme.txt")
        XCTAssertEqual(entries[1].uncompressedSize, 5)
        XCTAssertEqual(entries[2].uncompressedSize, 1500)
        XCTAssertNotNil(entries[1].modified)
    }

    // MARK: Gzip

    func testGzipHeader() throws {
        let data = FixtureBuilder.gzipHeader(originalName: "backup.tar")
        let file = try detect(data, ext: "gz")
        XCTAssertEqual(file.kind, .gzip)

        let document = try GzipRenderer().render(file)
        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected summary")
        }
        XCTAssertEqual(rows.first { $0.key == "Original file" }?.value, "backup.tar")
        XCTAssertEqual(rows.first { $0.key == "Created on" }?.value, "Unix")
        XCTAssertEqual(rows.first { $0.key == "Compression" }?.value, "deflate")
    }

    // MARK: NPY

    func testNPYHeader() throws {
        let data = FixtureBuilder.npy(descr: "<f4", shape: [3, 4])
        let file = try detect(data, ext: "npy")
        XCTAssertEqual(file.kind, .npy)

        let document = try NPYRenderer().render(file)
        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected array section")
        }
        XCTAssertEqual(rows.first { $0.key == "Data type" }?.value, "float32 (<f4)")
        XCTAssertEqual(rows.first { $0.key == "Shape" }?.value, "3 × 4")
        XCTAssertEqual(rows.first { $0.key == "Elements" }?.value, "12")
    }

    // MARK: AI image metadata

    func testAutomatic1111Extraction() {
        let parameters = "a cat in space\nNegative prompt: blurry, low quality\nSteps: 20, Sampler: Euler a, CFG scale: 7, Seed: 12345"
        let png = FixtureBuilder.pngTextChunks([("parameters", parameters)])

        let chunks = AIImageMetadata.textChunks(in: png)
        XCTAssertEqual(chunks["parameters"], parameters)

        let rows = AIImageMetadata.automatic1111Rows(parameters)
        XCTAssertEqual(rows.first { $0.key == "Prompt" }?.value, "a cat in space")
        XCTAssertEqual(rows.first { $0.key == "Negative prompt" }?.value, "blurry, low quality")
        XCTAssertEqual(rows.first { $0.key == "Steps" }?.value, "20")
        XCTAssertEqual(rows.first { $0.key == "Sampler" }?.value, "Euler a")
        XCTAssertEqual(rows.first { $0.key == "Seed" }?.value, "12345")
    }

    func testComfyUIExtraction() {
        let prompt = """
        {"1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "sdxl.safetensors"}},
         "2": {"class_type": "CLIPTextEncode", "inputs": {"text": "a fox", "clip": ["1", 1]}},
         "3": {"class_type": "KSampler", "inputs": {"sampler_name": "euler", "seed": 42, "steps": 30, "cfg": 8, "scheduler": "normal"}}}
        """
        let rows = AIImageMetadata.comfyUIRows(promptJSON: prompt, workflowJSON: nil)
        XCTAssertEqual(rows.first { $0.key == "Model" }?.value, "sdxl.safetensors")
        XCTAssertEqual(rows.first { $0.key == "Prompt" }?.value, "a fox")
        XCTAssertEqual(rows.first { $0.key == "Sampler" }?.value, "euler")
        XCTAssertEqual(rows.first { $0.key == "Seed" }?.value, "42")
        XCTAssertEqual(rows.first { $0.key == "Nodes" }?.value, "3")
    }

    // MARK: Image (real PNG via ImageIO)

    func testImageRenderer() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).png")
        temporaryFiles.append(url)

        let context = CGContext(
            data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .image(format: "PNG"))

        let document = try ImageRenderer().render(file)
        guard case .image = document.sections[0] else {
            return XCTFail("expected image section first")
        }
        guard case .keyValues(_, let rows) = document.sections[1] else {
            return XCTFail("expected metadata section")
        }
        XCTAssertEqual(rows.first { $0.key == "Dimensions" }?.value, "4 × 2")
    }

    // MARK: Media (real WAV via AVFoundation)

    func testMediaRendererWAV() async throws {
        let file = try detect(FixtureBuilder.wav(seconds: 2), ext: "wav")
        XCTAssertEqual(file.kind, .audio(format: "WAV"))

        let document = try await MediaRenderer().render(file)
        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected summary")
        }
        XCTAssertEqual(rows.first { $0.key == "Duration" }?.value, "0:02")
        guard case .keyValues(_, let tracks) = document.sections[1] else {
            return XCTFail("expected tracks")
        }
        XCTAssertTrue(tracks.contains { $0.key == "Audio" && $0.value.contains("8.0 kHz") })
    }

    // MARK: PDF (real PDF via CoreGraphics)

    func testPDFRenderer() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString).pdf")
        temporaryFiles.append(url)

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &mediaBox, [
            kCGPDFContextTitle: "Test Document",
            kCGPDFContextAuthor: "OmniPreview Tests",
        ] as CFDictionary)!
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()

        let file = try FileTypeDetector.detect(url: url)
        XCTAssertEqual(file.kind, .pdf)

        let document = try PDFRenderer().render(file)
        guard case .keyValues(_, let summary) = document.sections[0] else {
            return XCTFail("expected summary")
        }
        XCTAssertEqual(summary.first { $0.key == "Pages" }?.value, "2")
        XCTAssertEqual(summary.first { $0.key == "Page size" }?.value, "612 × 792 pt")

        guard case .keyValues(_, let info) = document.sections[1] else {
            return XCTFail("expected document info")
        }
        XCTAssertEqual(info.first { $0.key == "Title" }?.value, "Test Document")
        XCTAssertEqual(info.first { $0.key == "Author" }?.value, "OmniPreview Tests")
    }

    // MARK: Detection of new container kinds

    func testNewSignatures() {
        func kind(_ head: [UInt8], _ name: String) -> FileKind {
            FileTypeDetector.detectKind(head: Data(head), url: URL(fileURLWithPath: "/tmp/\(name)"))
        }
        XCTAssertEqual(kind([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "a.bin"), .image(format: "PNG"))
        XCTAssertEqual(kind([0xFF, 0xD8, 0xFF, 0xE0], "a.bin"), .image(format: "JPEG"))
        XCTAssertEqual(kind(Array("fLaC".utf8), "a.bin"), .audio(format: "FLAC"))
        XCTAssertEqual(kind(Array("RIFF").map { $0.asciiValue! } + [0, 0, 0, 0] + Array("WAVE".utf8), "a.bin"), .audio(format: "WAV"))
        XCTAssertEqual(kind(Array("RIFF").map { $0.asciiValue! } + [0, 0, 0, 0] + Array("WEBP".utf8), "a.bin"), .image(format: "WebP"))
        XCTAssertEqual(kind([0, 0, 0, 0x20] + Array("ftypheic".utf8), "a.bin"), .image(format: "HEIC"))
        XCTAssertEqual(kind([0, 0, 0, 0x20] + Array("ftypisom".utf8), "a.bin"), .video(format: "MP4"))
        XCTAssertEqual(kind([0x93] + Array("NUMPY".utf8), "a.bin"), .npy)
    }
}
