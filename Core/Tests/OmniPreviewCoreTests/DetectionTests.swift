import XCTest
@testable import OmniPreviewCore

final class DetectionTests: XCTestCase {

    private func kind(head: [UInt8], name: String) -> FileKind {
        FileTypeDetector.detectKind(head: Data(head), url: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    func testMagicByteDetection() {
        XCTAssertEqual(kind(head: [0x50, 0x4B, 0x03, 0x04], name: "a.bin"), .zip)
        XCTAssertEqual(kind(head: [0x1F, 0x8B, 0x08], name: "a.bin"), .gzip)
        XCTAssertEqual(kind(head: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], name: "a.bin"), .sevenZip)
        XCTAssertEqual(kind(head: Array("SQLite format 3\0".utf8), name: "a.bin"), .sqlite)
        XCTAssertEqual(kind(head: Array("GGUF".utf8), name: "a.bin"), .gguf)
        XCTAssertEqual(kind(head: Array("%PDF-1.7".utf8), name: "a.bin"), .pdf)
        XCTAssertEqual(kind(head: Array("OTTO".utf8), name: "a.bin"), .font)
        XCTAssertEqual(kind(head: Array("-----BEGIN CERTIFICATE-----".utf8), name: "a.bin"), .pemCertificate)
    }

    func testSignatureBeatsMisleadingExtension() {
        // A ZIP renamed to .txt must still be detected as ZIP.
        XCTAssertEqual(kind(head: [0x50, 0x4B, 0x03, 0x04], name: "fake.txt"), .zip)
    }

    func testTarDetectionAtOffset257() {
        var head = [UInt8](repeating: 0, count: 512)
        head.replaceSubrange(257..<262, with: Array("ustar".utf8))
        XCTAssertEqual(kind(head: head, name: "a.bin"), .tar)
    }

    func testSourceCodeFallbackByExtension() {
        XCTAssertEqual(kind(head: Array("import Foundation".utf8), name: "main.swift"), .sourceCode(language: "Swift"))
        XCTAssertEqual(kind(head: Array("FROM ubuntu".utf8), name: "Dockerfile"), .sourceCode(language: "Dockerfile"))
        XCTAssertEqual(kind(head: [0x00, 0xFF, 0x13], name: "mystery.xyz"), .unknown)
    }

    func testExtensionlessPlainTextFallback() {
        XCTAssertEqual(
            kind(head: Array("hello from extensionless text\n".utf8), name: "README"),
            .sourceCode(language: "Plain Text")
        )
    }

    func testUTF16BOMIsDetectedAsText() {
        let utf16Sample: [UInt8] = [0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00, 0x0A, 0x00]
        XCTAssertEqual(kind(head: utf16Sample, name: "notes"), .sourceCode(language: "Plain Text"))
    }

    func testSafetensorsHeuristic() {
        var head: [UInt8] = [16, 0, 0, 0, 0, 0, 0, 0] // header length 16
        head.append(UInt8(ascii: "{"))
        XCTAssertEqual(kind(head: head, name: "model.safetensors"), .safetensors)
        // Same bytes without the extension must not match.
        XCTAssertEqual(kind(head: head, name: "model.bin"), .unknown)
    }
}
