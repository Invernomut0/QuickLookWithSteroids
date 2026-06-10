import SwiftUI
import AVKit
import AVFoundation

/// Pro feature: trim a video using the native AVPlayerView trim UI and
/// export the result to a user-chosen file via NSSavePanel.
struct VideoTrimSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var exportStatus: ExportStatus = .idle

    enum ExportStatus: Equatable {
        case idle, exporting(Double), done(URL), failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                exportButton
            }
            .padding(12)
            .background(Material.bar)

            Divider()

            // Player with trim handles
            AVPlayerRepresentable(url: url, exportStatus: $exportStatus)
                .frame(minHeight: 360)

            // Export progress / result
            statusBar
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder
    private var exportButton: some View {
        switch exportStatus {
        case .idle:
            Button("Export Trimmed…") { exportStatus = .exporting(0) }
                .buttonStyle(.borderedProminent)
        case .exporting(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("Exporting…")
                    .foregroundStyle(.secondary)
            }
        case .done:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg)
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if case .done(let output) = exportStatus {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Exported to \(output.lastPathComponent)")
                    .font(.callout)
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(output.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.link)
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
        }
    }
}

// MARK: NSViewRepresentable

private struct AVPlayerRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var exportStatus: VideoTrimSheet.ExportStatus

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = AVPlayer(url: url)
        view.showsTimecodes = true
        view.controlsStyle = .inline
        view.allowsMagnification = true
        return view
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        // Trigger export when status changes to .exporting
        guard case .exporting = exportStatus else { return }

        // Use beginTrimming so the trim handles are already set by the user.
        if playerView.canBeginTrimming {
            playerView.beginTrimming { result in
                guard result == .okButton else {
                    exportStatus = .idle
                    return
                }
                Task {
                    await export(player: playerView.player, status: $exportStatus)
                }
            }
        } else {
            // Player not ready for trimming yet; show trim UI immediately
            exportStatus = .idle
        }
    }

    // MARK: Export

    @MainActor
    private func export(player: AVPlayer?, status: Binding<VideoTrimSheet.ExportStatus>) async {
        guard let player,
              let item = player.currentItem else {
            status.wrappedValue = .failed("Player is not ready.")
            return
        }

        let asset = item.asset

        // Resolve the trim range from the player item.
        let duration: CMTime
        if let d = try? await asset.load(.duration) { duration = d }
        else { status.wrappedValue = .failed("Could not read video duration."); return }

        let startTime = item.reversePlaybackEndTime == .negativeInfinity
            ? .zero
            : item.reversePlaybackEndTime
        let endTime = item.forwardPlaybackEndTime == .positiveInfinity
            ? duration
            : item.forwardPlaybackEndTime

        let timeRange = CMTimeRange(start: startTime, end: endTime)

        // Ask the user where to save.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "-trimmed.mp4"

        guard panel.runModal() == .OK, let destination = panel.url else {
            status.wrappedValue = .idle
            return
        }

        // Remove existing file if present (export session won't overwrite).
        try? FileManager.default.removeItem(at: destination)

        guard let session = AVAssetExportSession(asset: asset,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            status.wrappedValue = .failed("Could not create export session.")
            return
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.timeRange = timeRange

        // Stream progress updates.
        let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        let cancellable = timer.sink { _ in
            status.wrappedValue = .exporting(Double(session.progress))
        }

        await session.export()
        cancellable.cancel()

        switch session.status {
        case .completed:
            status.wrappedValue = .done(destination)
        case .failed:
            status.wrappedValue = .failed(session.error?.localizedDescription ?? "Export failed.")
        default:
            status.wrappedValue = .idle
        }
    }
}
