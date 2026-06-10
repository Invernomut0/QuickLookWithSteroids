import Foundation
import Compression

/// Streaming decompression with a hard output cap, so a small hostile file
/// can never expand into unbounded memory (decompression-bomb protection).
enum Decompressor {

    struct Result {
        let data: Data
        let truncated: Bool
    }

    /// Raw DEFLATE (ZIP entries, gzip payloads).
    static func inflateRaw(_ input: Data, maxOutput: Int) -> Result? {
        decompress(input, algorithm: COMPRESSION_ZLIB, maxOutput: maxOutput)
    }

    /// XZ container (Compression framework's LZMA implementation).
    static func inflateXZ(_ input: Data, maxOutput: Int) -> Result? {
        decompress(input, algorithm: COMPRESSION_LZMA, maxOutput: maxOutput)
    }

    /// Gzip member: parses the RFC 1952 header, then inflates the payload.
    static func inflateGzip(_ input: Data, maxOutput: Int) -> Result? {
        guard let payloadStart = gzipPayloadOffset(input) else { return nil }
        return inflateRaw(input.subdata(in: payloadStart..<input.count), maxOutput: maxOutput)
    }

    static func gzipPayloadOffset(_ input: Data) -> Int? {
        var reader = DataReader(input)
        guard let magic = try? reader.read(2), magic == [0x1F, 0x8B],
              let _ = try? reader.readU8(), // method
              let flags = try? reader.readU8(),
              (try? reader.skip(6)) != nil else { return nil }
        if flags & 0x04 != 0, let extraLength = try? reader.readU16LE() {
            guard (try? reader.skip(Int(extraLength))) != nil else { return nil }
        }
        if flags & 0x08 != 0 { // FNAME
            while let byte = try? reader.readU8(), byte != 0 {}
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while let byte = try? reader.readU8(), byte != 0 {}
        }
        if flags & 0x02 != 0 { // FHCRC
            guard (try? reader.skip(2)) != nil else { return nil }
        }
        return reader.offset
    }

    private static func decompress(_ input: Data, algorithm: compression_algorithm, maxOutput: Int) -> Result? {
        guard !input.isEmpty, maxOutput > 0 else { return nil }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        let chunkSize = 256 * 1024
        var output = Data()
        var truncated = false
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        let succeeded: Bool = input.withUnsafeBytes { (rawInput: UnsafeRawBufferPointer) -> Bool in
            guard let base = rawInput.bindMemory(to: UInt8.self).baseAddress else { return false }
            stream.src_ptr = base
            stream.src_size = input.count

            while true {
                stream.dst_ptr = buffer
                stream.dst_size = chunkSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    output.append(buffer, count: chunkSize - stream.dst_size)
                    if output.count >= maxOutput {
                        truncated = status != COMPRESSION_STATUS_END
                        if truncated { output = output.prefix(maxOutput) }
                        return true
                    }
                    if status == COMPRESSION_STATUS_END { return true }
                default:
                    return false
                }
            }
        }
        return succeeded ? Result(data: output, truncated: truncated) : nil
    }
}
