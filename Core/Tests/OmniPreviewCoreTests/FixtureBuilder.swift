import Foundation

/// Builds tiny, valid binary fixtures in memory so tests are deterministic
/// and need no bundled sample files.
enum FixtureBuilder {

    static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Minimal ZIP with stored (uncompressed) entries.
    static func zip(entries: [(name: String, content: Data)]) -> Data {
        var data = Data()
        var centralDirectory = Data()
        var localOffsets: [UInt32] = []

        for entry in entries {
            localOffsets.append(UInt32(data.count))
            let name = Data(entry.name.utf8)
            appendLE(UInt32(0x04034b50), to: &data) // local file header
            appendLE(UInt16(20), to: &data)         // version needed
            appendLE(UInt16(0), to: &data)          // flags
            appendLE(UInt16(0), to: &data)          // method: stored
            appendLE(UInt16(0), to: &data)          // time
            appendLE(UInt16(0x58C1), to: &data)     // date: 2024-06-01
            appendLE(UInt32(0), to: &data)          // crc (not validated by reader)
            appendLE(UInt32(entry.content.count), to: &data)
            appendLE(UInt32(entry.content.count), to: &data)
            appendLE(UInt16(name.count), to: &data)
            appendLE(UInt16(0), to: &data)          // extra length
            data.append(name)
            data.append(entry.content)
        }

        for (index, entry) in entries.enumerated() {
            let name = Data(entry.name.utf8)
            appendLE(UInt32(0x02014b50), to: &centralDirectory)
            appendLE(UInt16(20), to: &centralDirectory) // version made by
            appendLE(UInt16(20), to: &centralDirectory) // version needed
            appendLE(UInt16(0), to: &centralDirectory)  // flags
            appendLE(UInt16(0), to: &centralDirectory)  // method
            appendLE(UInt16(0), to: &centralDirectory)  // time
            appendLE(UInt16(0x58C1), to: &centralDirectory)
            appendLE(UInt32(0), to: &centralDirectory)  // crc
            appendLE(UInt32(entry.content.count), to: &centralDirectory)
            appendLE(UInt32(entry.content.count), to: &centralDirectory)
            appendLE(UInt16(name.count), to: &centralDirectory)
            appendLE(UInt16(0), to: &centralDirectory)  // extra
            appendLE(UInt16(0), to: &centralDirectory)  // comment
            appendLE(UInt16(0), to: &centralDirectory)  // disk start
            appendLE(UInt16(0), to: &centralDirectory)  // internal attrs
            appendLE(UInt32(0), to: &centralDirectory)  // external attrs
            appendLE(localOffsets[index], to: &centralDirectory)
            centralDirectory.append(name)
        }

        let cdOffset = UInt32(data.count)
        data.append(centralDirectory)
        appendLE(UInt32(0x06054b50), to: &data) // end of central directory
        appendLE(UInt16(0), to: &data)          // disk number
        appendLE(UInt16(0), to: &data)          // cd start disk
        appendLE(UInt16(entries.count), to: &data)
        appendLE(UInt16(entries.count), to: &data)
        appendLE(UInt32(centralDirectory.count), to: &data)
        appendLE(cdOffset, to: &data)
        appendLE(UInt16(0), to: &data)          // comment length
        return data
    }

    static func safetensors(header: [String: Any], dataBytes: Int) -> Data {
        let json = try! JSONSerialization.data(withJSONObject: header)
        var data = Data()
        appendLE(UInt64(json.count), to: &data)
        data.append(json)
        data.append(Data(count: dataBytes))
        return data
    }

    static func gguf(metadata: [(key: String, value: String)], tensorCount: UInt64 = 0) -> Data {
        var data = Data(Array("GGUF".utf8))
        appendLE(UInt32(3), to: &data)
        appendLE(tensorCount, to: &data)
        appendLE(UInt64(metadata.count), to: &data)
        for (key, value) in metadata {
            appendLE(UInt64(key.utf8.count), to: &data)
            data.append(Data(key.utf8))
            appendLE(UInt32(8), to: &data) // string type
            appendLE(UInt64(value.utf8.count), to: &data)
            data.append(Data(value.utf8))
        }
        return data
    }

    /// POSIX ustar archive with optional directory entries.
    static func tar(entries: [(name: String, content: Data, isDirectory: Bool)]) -> Data {
        var data = Data()
        for entry in entries {
            var header = [UInt8](repeating: 0, count: 512)
            let name = Array(entry.name.utf8.prefix(100))
            header.replaceSubrange(0..<name.count, with: name)
            let sizeOctal = Array(String(format: "%011o", entry.content.count).utf8)
            header.replaceSubrange(124..<124 + sizeOctal.count, with: sizeOctal)
            let mtimeOctal = Array(String(format: "%011o", 1_700_000_000).utf8)
            header.replaceSubrange(136..<136 + mtimeOctal.count, with: mtimeOctal)
            header[156] = entry.isDirectory ? UInt8(ascii: "5") : UInt8(ascii: "0")
            header.replaceSubrange(257..<262, with: Array("ustar".utf8))
            data.append(contentsOf: header)
            data.append(entry.content)
            let padding = (512 - entry.content.count % 512) % 512
            data.append(Data(count: padding))
        }
        data.append(Data(count: 1024)) // two terminating zero blocks
        return data
    }

    /// Gzip header with FNAME; the deflate body is junk (never read by the renderer).
    static func gzipHeader(originalName: String) -> Data {
        var data = Data([0x1F, 0x8B, 0x08, 0x08])
        appendLE(UInt32(1_700_000_000), to: &data) // mtime
        data.append(contentsOf: [0x00, 0x03])      // extra flags, OS = Unix
        data.append(Data(originalName.utf8))
        data.append(0)
        data.append(Data([0xAB, 0xCD, 0xEF]))
        return data
    }

    static func npy(descr: String, shape: [Int]) -> Data {
        let shapeText = shape.map(String.init).joined(separator: ", ") + (shape.count == 1 ? "," : "")
        var header = "{'descr': '\(descr)', 'fortran_order': False, 'shape': (\(shapeText)), }"
        while (header.count + 10) % 64 != 0 { header += " " }
        var data = Data([0x93] + Array("NUMPY".utf8) + [0x01, 0x00])
        appendLE(UInt16(header.count), to: &data)
        data.append(Data(header.utf8))
        return data
    }

    /// PNG signature + tEXt chunks + IEND. Chunk CRCs are zero — the chunk
    /// scanner does not validate them.
    static func pngTextChunks(_ chunks: [(keyword: String, text: String)]) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        for chunk in chunks {
            var body = Data(chunk.keyword.utf8)
            body.append(0)
            body.append(Data(chunk.text.utf8))
            withUnsafeBytes(of: UInt32(body.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(Data("tEXt".utf8))
            data.append(body)
            data.append(Data(count: 4)) // crc
        }
        withUnsafeBytes(of: UInt32(0).bigEndian) { data.append(contentsOf: $0) }
        data.append(Data("IEND".utf8))
        data.append(Data(count: 4))
        return data
    }

    /// Minimal PCM WAV: 8-bit mono at 8 kHz.
    static func wav(seconds: Double) -> Data {
        let sampleCount = Int(8000 * seconds)
        var data = Data("RIFF".utf8)
        appendLE(UInt32(36 + sampleCount), to: &data)
        data.append(Data("WAVEfmt ".utf8))
        appendLE(UInt32(16), to: &data)   // fmt chunk size
        appendLE(UInt16(1), to: &data)    // PCM
        appendLE(UInt16(1), to: &data)    // mono
        appendLE(UInt32(8000), to: &data) // sample rate
        appendLE(UInt32(8000), to: &data) // byte rate
        appendLE(UInt16(1), to: &data)    // block align
        appendLE(UInt16(8), to: &data)    // bits per sample
        data.append(Data("data".utf8))
        appendLE(UInt32(sampleCount), to: &data)
        data.append(Data(repeating: 0x80, count: sampleCount))
        return data
    }

    static func write(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipreview-test-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }
}
