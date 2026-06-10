import Foundation
import AVFoundation

/// Audio/video metadata via AVFoundation: duration, codecs, resolution,
/// bitrate, and common tags. Decoding is left to the system.
public struct MediaRenderer: PreviewRenderer {
    public static let id = "media"
    public static let displayName = "Audio & Video"

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        switch file.kind {
        case .audio, .video: return true
        default: return false
        }
    }

    public func render(_ file: DetectedFile) async throws -> PreviewDocument {
        let isVideo: Bool
        let format: String
        switch file.kind {
        case .audio(let f): isVideo = false; format = f
        case .video(let f): isVideo = true; format = f
        default: throw PreviewError.unsupportedType
        }

        let asset = AVURLAsset(url: file.url)
        // Load metadata defensively: some containers expose duration but fail
        // track or tag loading. We still want a useful summary instead of a
        // hard error.
        let duration = (try? await asset.load(.duration)) ?? .zero
        let tracks = (try? await asset.load(.tracks)) ?? []
        let metadata = (try? await asset.load(.commonMetadata)) ?? []

        var rows = [
            KeyValueRow("Duration", Self.timeString(duration.seconds)),
            KeyValueRow("Container", format),
            KeyValueRow("File size", Format.bytes(file.fileSize)),
        ]
        if duration.seconds > 0 {
            let bitsPerSecond = Double(file.fileSize) * 8 / duration.seconds
            rows.append(KeyValueRow("Overall bitrate", String(format: "%.0f kb/s", bitsPerSecond / 1000)))
        }

        var trackRows: [KeyValueRow] = []
        for track in tracks {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let codec = descriptions.first.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
            switch track.mediaType {
            case .video:
                let size = (try? await track.load(.naturalSize)) ?? .zero
                let fps = (try? await track.load(.nominalFrameRate)) ?? 0
                var detail = "\(codec), \(Int(size.width)) × \(Int(size.height))"
                if fps > 0 { detail += String(format: ", %.3g fps", fps) }
                trackRows.append(KeyValueRow("Video", detail))
            case .audio:
                var detail = codec
                if let audioDescription = descriptions.first,
                   let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription)?.pointee {
                    detail += String(format: ", %.1f kHz", streamDescription.mSampleRate / 1000)
                    detail += streamDescription.mChannelsPerFrame == 1 ? ", mono" : ", \(streamDescription.mChannelsPerFrame) ch"
                }
                trackRows.append(KeyValueRow("Audio", detail))
            default:
                trackRows.append(KeyValueRow(track.mediaType.rawValue.capitalized, codec))
            }
        }

        var tagRows: [KeyValueRow] = []
        let tagIdentifiers: [(AVMetadataIdentifier, String)] = [
            (.commonIdentifierTitle, "Title"),
            (.commonIdentifierArtist, "Artist"),
            (.commonIdentifierAlbumName, "Album"),
            (.commonIdentifierCreationDate, "Date"),
        ]
        for (identifier, label) in tagIdentifiers {
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
            if let item = items.first, let value = try? await item.load(.stringValue) {
                tagRows.append(KeyValueRow(label, value))
            }
        }

        var sections: [PreviewSection] = [.keyValues(title: "Summary", rows: rows)]
        if !trackRows.isEmpty {
            sections.append(.keyValues(title: "Tracks", rows: trackRows))
        } else {
            sections.append(.note("Track metadata unavailable for this container/codec"))
        }
        if !tagRows.isEmpty { sections.append(.keyValues(title: "Tags", rows: tagRows)) }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: isVideo ? "\(format) Video" : "\(format) Audio",
            iconSystemName: isVideo ? "film" : "waveform",
            sections: sections
        )
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text.trimmingCharacters(in: .whitespaces)
    }
}
