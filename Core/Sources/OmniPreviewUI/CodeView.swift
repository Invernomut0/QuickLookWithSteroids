import SwiftUI
import AppKit

/// Non-editable, selectable NSTextView that displays an attributed string.
/// Height is sized to fit content (capped at `maxHeight`) so the parent
/// SwiftUI ScrollView handles all overflow.
struct CodeView: NSViewRepresentable {
    let attributedString: NSAttributedString
    var maxHeight: CGFloat = 800

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        // Allow horizontal scrolling for long lines.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
    }

    /// Estimate height from line count so SwiftUI can size the view before
    /// layout without measuring the NSTextView.
    static func estimatedHeight(for text: String, lineHeight: CGFloat = 16,
                                 padding: CGFloat = 20, max: CGFloat = 800) -> CGFloat {
        let lines = text.components(separatedBy: "\n").count
        return min(CGFloat(lines) * lineHeight + padding, max)
    }
}
