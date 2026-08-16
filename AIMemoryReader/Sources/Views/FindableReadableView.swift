#if os(macOS)
import AppKit
import SwiftUI

/// Read-only document view used while the in-page find bar is active.
///
/// Shows a simplified markdown rendering (produced by `ReadableMarkdownRenderer`)
/// inside an `NSTextView` so matched substrings can be highlighted at
/// character granularity — something MarkdownUI can't do because it doesn't
/// expose per-run position information.
struct FindableReadableView: NSViewRepresentable {
    /// The pre-rendered attributed document. Parent owns this and re-creates
    /// it only when the raw content or theme palette changes, so this view
    /// doesn't re-parse markdown on every keystroke.
    let baseAttributed: NSAttributedString
    /// Ranges in `baseAttributed.string` that the find query matched.
    let matchRanges: [NSRange]
    /// Index of the currently-focused match (0-based). Ignored when
    /// `matchRanges` is empty.
    let currentIndex: Int
    let palette: ThemePalette
    /// Called when a link is clicked. Returns true when the app handled it
    /// itself, which keeps the system out of it.
    let onLink: (URL) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = false

        let textView = ReadableTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 12)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isRichText = true
        textView.allowsUndo = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize =
            NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(palette.link),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]

        textView.onLink = onLink

        scrollView.documentView = textView
        context.coordinator.textView = textView

        applyStorage(on: textView)
        scrollToCurrentMatch(in: textView, animated: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReadableTextView else { return }
        textView.onLink = onLink
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(palette.link),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        if !context.coordinator.baseMatches(baseAttributed) {
            applyStorage(on: textView)
            context.coordinator.lastBaseHash = baseAttributed.length
            context.coordinator.lastBaseString = baseAttributed.string
        } else {
            // Same document — only find highlights changed. Repaint backgrounds.
            applyFindHighlights(on: textView)
        }
        scrollToCurrentMatch(in: textView, animated: true)
    }

    // MARK: - Helpers

    private func applyStorage(on textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        storage.setAttributedString(baseAttributed)
        applyFindHighlights(on: textView)
    }

    private func applyFindHighlights(on textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        // Reset any previously-painted find backgrounds. We do this by
        // re-running the renderer's background attribute path: for each
        // character, restore the base attributed string's background.
        let base = baseAttributed
        base.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            if let color = value as? NSColor {
                storage.addAttribute(.backgroundColor, value: color, range: range)
            } else {
                storage.removeAttribute(.backgroundColor, range: range)
            }
        }

        let matchColor = NSColor(palette.findMatch)
        let currentColor = NSColor(palette.findCurrent)
        for (i, range) in matchRanges.enumerated() {
            guard range.location + range.length <= storage.length else { continue }
            let color = (i == currentIndex) ? currentColor : matchColor
            storage.addAttribute(.backgroundColor, value: color, range: range)
        }
        storage.endEditing()
    }

    private func scrollToCurrentMatch(in textView: NSTextView, animated: Bool) {
        guard matchRanges.indices.contains(currentIndex) else { return }
        let range = matchRanges[currentIndex]
        guard let storage = textView.textStorage,
              range.location + range.length <= storage.length else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                textView.scrollRangeToVisible(range)
            }
        } else {
            textView.scrollRangeToVisible(range)
        }
        // Show the system find-indicator bubble over the match for
        // extra visibility, like Safari's ⌘F.
        textView.showFindIndicator(for: range)
    }

    final class Coordinator: NSObject {
        weak var textView: ReadableTextView?
        var lastBaseHash: Int = -1
        var lastBaseString: String = ""

        func baseMatches(_ attributed: NSAttributedString) -> Bool {
            lastBaseHash == attributed.length && lastBaseString == attributed.string
        }
    }
}

/// NSTextView that gives the app first refusal on link clicks, so a link to a
/// neighbouring memory file navigates in place instead of launching whatever
/// app owns `.md`. Anything the app declines falls through to the system.
final class ReadableTextView: NSTextView {
    var onLink: ((URL) -> Bool)?

    override func clicked(onLink link: Any, at charIndex: Int) {
        let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
        if let url, onLink?(url) == true { return }
        super.clicked(onLink: link, at: charIndex)
    }
}
#endif
