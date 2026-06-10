import Foundation

/// Bounds-checked sequential reader over a byte buffer. All binary parsers
/// go through this so malformed files fail with `.corruptFile` instead of
/// crashing or over-reading.
struct DataReader {
    private let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }

    var remaining: Int { bytes.count - offset }

    mutating func read(_ count: Int) throws -> [UInt8] {
        guard count >= 0, remaining >= count else {
            throw PreviewError.corruptFile("unexpected end of data at offset \(offset)")
        }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, remaining >= count else {
            throw PreviewError.corruptFile("unexpected end of data at offset \(offset)")
        }
        offset += count
    }

    mutating func readU8() throws -> UInt8 { try read(1)[0] }

    mutating func readU16LE() throws -> UInt16 {
        let b = try read(2)
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func readU32LE() throws -> UInt32 {
        let b = try read(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func readU32BE() throws -> UInt32 {
        let b = try read(4)
        return UInt32(b[3]) | UInt32(b[2]) << 8 | UInt32(b[1]) << 16 | UInt32(b[0]) << 24
    }

    mutating func readU64LE() throws -> UInt64 {
        let b = try read(8)
        var value: UInt64 = 0
        for i in (0..<8).reversed() { value = value << 8 | UInt64(b[i]) }
        return value
    }

    mutating func readString(_ count: Int) throws -> String {
        let b = try read(count)
        return String(decoding: b, as: UTF8.self)
    }
}
