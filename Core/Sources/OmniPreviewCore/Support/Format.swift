import Foundation

enum Format {
    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
