import XCTest
@testable import OmniPreviewCore

final class YAMLAndDMGTests: XCTestCase {
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

    // MARK: YAML

    func testKubernetesManifestDetection() throws {
        let yaml = """
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web-frontend
          namespace: production
        spec:
          template:
            spec:
              containers:
                - name: app
                  image: nginx:1.27
        """
        let file = try detect(Data(yaml.utf8), name: "deploy.yaml")
        let document = try YAMLRenderer().render(file)
        XCTAssertEqual(document.subtitle, "Kubernetes Manifest")
        let rows = keyValues(document)
        XCTAssertEqual(rows.first { $0.key == "Resources" }?.value, "Deployment")
        XCTAssertEqual(rows.first { $0.key == "Name" }?.value, "web-frontend")
        XCTAssertEqual(rows.first { $0.key == "Namespace" }?.value, "production")
        XCTAssertEqual(rows.first { $0.key == "Images" }?.value, "nginx:1.27")
    }

    func testDockerComposeDetection() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            ports:
              - "80:80"
          db:
            image: postgres:16
        volumes:
          pgdata:
        """
        let file = try detect(Data(yaml.utf8), name: "docker-compose.yml")
        let document = try YAMLRenderer().render(file)
        XCTAssertEqual(document.subtitle, "Docker Compose")
        let rows = keyValues(document)
        XCTAssertEqual(rows.first { $0.key == "Services" }?.value, "web, db")
        XCTAssertEqual(rows.first { $0.key == "Images" }?.value, "nginx:latest, postgres:16")
    }

    func testGitHubActionsDetection() throws {
        let yaml = """
        name: CI
        on:
          push:
            branches: [main]
        jobs:
          test:
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4
              - name: Run tests
                run: swift test
          build:
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4
        """
        let file = try detect(Data(yaml.utf8), name: "ci.yml")
        let document = try YAMLRenderer().render(file)
        XCTAssertEqual(document.subtitle, "GitHub Actions Workflow")
        let rows = keyValues(document)
        XCTAssertEqual(rows.first { $0.key == "Workflow" }?.value, "CI")
        XCTAssertEqual(rows.first { $0.key == "Jobs" }?.value, "test, build")
        XCTAssertEqual(rows.first { $0.key == "Steps" }?.value, "3")
    }

    func testPlainYAMLFallback() throws {
        let yaml = "title: hello\nitems:\n  - a\n  - b\n"
        let file = try detect(Data(yaml.utf8), name: "config.yaml")
        let document = try YAMLRenderer().render(file)
        XCTAssertEqual(document.subtitle, "YAML Document")
        let rows = keyValues(document)
        XCTAssertEqual(rows.first { $0.key == "Top-level keys" }?.value, "title, items")
    }

    // MARK: DMG

    func testDMGPartitionListing() throws {
        // Build a minimal UDIF: XML plist with two blkx partitions, then a
        // 512-byte koly trailer pointing at it.
        let plist: [String: Any] = [
            "resource-fork": [
                "blkx": [
                    ["Name": "Protective Master Boot Record (MBR : 0)"],
                    ["Name": "Apple_HFS (Apple_HFS : 1)"],
                ],
            ],
        ]
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        var trailer = [UInt8](repeating: 0, count: 512)
        trailer.replaceSubrange(0..<4, with: Array("koly".utf8))
        func putU32BE(_ value: UInt32, at offset: Int) {
            withUnsafeBytes(of: value.bigEndian) { trailer.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        func putU64BE(_ value: UInt64, at offset: Int) {
            withUnsafeBytes(of: value.bigEndian) { trailer.replaceSubrange(offset..<offset + 8, with: $0) }
        }
        putU32BE(4, at: 4)                       // UDIF version
        putU64BE(0, at: 0xD8)                    // XML offset
        putU64BE(UInt64(xml.count), at: 0xE0)    // XML length
        putU64BE(2048, at: 0x1EC)                // sector count (1 MB)

        let data = xml + Data(trailer)
        let file = try detect(data, name: "installer.dmg")
        XCTAssertEqual(file.kind, .dmg)

        let document = try ArchiveMetadataRenderer().render(file)
        let summary = keyValues(document, section: 0)
        XCTAssertEqual(summary.first { $0.key == "Uncompressed size" }?.value, Format.bytes(2048 * 512))
        XCTAssertEqual(summary.first { $0.key == "Partitions" }?.value, "2")
        let partitions = keyValues(document, section: 1)
        XCTAssertEqual(partitions.count, 2)
        XCTAssertTrue(partitions[1].value.contains("Apple_HFS"))
    }
}
