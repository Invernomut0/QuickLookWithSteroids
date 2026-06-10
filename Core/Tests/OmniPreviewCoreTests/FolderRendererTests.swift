import XCTest
@testable import OmniPreviewCore

final class FolderRendererTests: XCTestCase {

    // Builds a temp directory tree, runs the renderer, then cleans up.
    private var rootURL: URL?

    override func setUp() {
        super.setUp()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-folder-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rootURL = root
    }

    override func tearDown() {
        if let root = rootURL { try? FileManager.default.removeItem(at: root) }
        super.tearDown()
    }

    private func create(_ path: String, content: String = "x") throws {
        let url = rootURL!.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if path.hasSuffix("/") {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent().appendingPathComponent(String(path.dropLast())), withIntermediateDirectories: true)
        } else {
            try content.data(using: .utf8)!.write(to: url)
        }
    }

    func testFolderDetectedAsFolder() throws {
        let root = rootURL!
        let file = try FileTypeDetector.detect(url: root)
        XCTAssertEqual(file.kind, .folder)
    }

    func testFolderRendererSummary() throws {
        let root = rootURL!
        // Create: 2 files + 1 subdir with 1 file inside
        try "hello".data(using: .utf8)!.write(to: root.appendingPathComponent("readme.md"))
        try "world".data(using: .utf8)!.write(to: root.appendingPathComponent("main.swift"))
        let sub = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "fn".data(using: .utf8)!.write(to: sub.appendingPathComponent("lib.rs"))

        let file = try FileTypeDetector.detect(url: root)
        let document = try FolderRenderer().render(file)

        guard case .keyValues(_, let rows) = document.sections[0] else {
            return XCTFail("expected summary section")
        }
        XCTAssertEqual(rows.first { $0.key == "Items" }?.value, "4")
        XCTAssertEqual(rows.first { $0.key == "Subfolders" }?.value, "1")
        XCTAssertEqual(rows.first { $0.key == "Files" }?.value, "3")
    }

    func testFolderTreeStructure() throws {
        let root = rootURL!
        try "a".data(using: .utf8)!.write(to: root.appendingPathComponent("a.txt"))
        let sub = root.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "b".data(using: .utf8)!.write(to: sub.appendingPathComponent("b.py"))

        let file = try FileTypeDetector.detect(url: root)
        let document = try FolderRenderer().render(file)

        guard case .folderTree(let nodes) = document.sections[1] else {
            return XCTFail("expected folderTree section")
        }
        // Folders come first: subdir, then a.txt
        XCTAssertEqual(nodes.first?.name, "subdir")
        XCTAssertTrue(nodes.first!.isDirectory)
        XCTAssertNotNil(nodes.first!.children)
        XCTAssertEqual(nodes.first!.children?.first?.name, "b.py")
        XCTAssertEqual(nodes.last?.name, "a.txt")
        XCTAssertFalse(nodes.last!.isDirectory)
    }

    func testIconMapping() {
        let pairs: [(String, String)] = [
            ("photo.jpg", "photo"),
            ("clip.mp4", "film"),
            ("song.flac", "waveform"),
            ("report.pdf", "doc.richtext"),
            ("archive.zip", "doc.zipper"),
            ("main.swift", "chevron.left.forwardslash.chevron.right"),
            ("config.yaml", "doc.badge.gearshape"),
            ("model.gguf", "brain"),
            ("part.stl", "cube"),
        ]
        for (filename, expectedIcon) in pairs {
            let url = URL(fileURLWithPath: "/tmp/\(filename)")
            XCTAssertEqual(FolderRenderer.iconName(for: url, isDirectory: false), expectedIcon,
                           "wrong icon for \(filename)")
        }
        XCTAssertEqual(FolderRenderer.iconName(for: URL(fileURLWithPath: "/tmp/dir"), isDirectory: true), "folder.fill")
    }

    func testRegistryHandlesFolderKind() {
        let file = DetectedFile(url: URL(fileURLWithPath: "/tmp"), kind: .folder, fileSize: 0)
        XCTAssertEqual(type(of: RendererRegistry.renderer(for: file)!).id, FolderRenderer.id)
    }
}
