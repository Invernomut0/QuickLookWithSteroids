import Foundation

/// Replaces a Pro renderer when the user has no active license.
/// Produces a `PreviewDocument` with a `.proLocked` section that the UI
/// renders as a prominent "upgrade" card.
struct LockedRenderer: PreviewRenderer {
    static let id = "_locked"
    static let displayName = "Pro Feature"

    let formatName: String
    let iconSystemName: String

    func canRender(_ file: DetectedFile) -> Bool { false }

    func render(_ file: DetectedFile) async throws -> PreviewDocument {
        PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: "\(formatName) · Pro Feature",
            iconSystemName: "lock.fill",
            sections: [
                .proLocked(formatName: formatName, iconSystemName: iconSystemName),
            ]
        )
    }
}
