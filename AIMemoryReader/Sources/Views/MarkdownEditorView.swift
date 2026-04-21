#if os(macOS)
import AppKit
import SwiftUI

extension Notification.Name {
    static let editorShowFindBar = Notification.Name("editorShowFindBar")
}

// MARK: - Markdown Editor View (NSTextView wrapper with syntax highlighting)

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Line number ruler
        let textView = HighlightingTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Monospace font
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.3)
        textView.insertionPointColor = NSColor.controlAccentColor

        // Text container sizing
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Line number ruler
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // Set initial text
        textView.string = text
        context.coordinator.applyHighlighting()

        // Observe text changes
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }

        // Only update if text actually changed from outside
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyHighlighting()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: HighlightingTextView?
        private var isUpdating = false
        private var findObserver: NSObjectProtocol?

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            super.init()
            findObserver = NotificationCenter.default.addObserver(
                forName: .editorShowFindBar,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.showFindBar()
                }
            }
        }

        deinit {
            if let obs = findObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        @MainActor
        private func showFindBar() {
            guard let textView else { return }
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.window?.makeFirstResponder(textView)
            textView.performTextFinderAction(item)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            isUpdating = true
            parent.text = textView.string
            parent.onTextChange?(textView.string)
            applyHighlighting()
            isUpdating = false

            // Update ruler
            if let scrollView = textView.enclosingScrollView,
               let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
        }

        func applyHighlighting() {
            guard let textView, let textStorage = textView.textStorage else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            textStorage.beginEditing()

            // Reset to base style
            let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            textStorage.setAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.textColor
            ], range: fullRange)

            // Apply markdown highlighting
            MarkdownHighlighter.highlight(textStorage: textStorage, in: text)

            textStorage.endEditing()
        }
    }
}

// MARK: - Custom NSTextView subclass

class HighlightingTextView: NSTextView {
    override func didChangeText() {
        super.didChangeText()
    }
}

// MARK: - Markdown Syntax Highlighter

enum MarkdownHighlighter {
    static func highlight(textStorage: NSTextStorage, in text: String) {
        let nsText = text as NSString
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Colors
        let headingColor = isDark ? NSColor.systemBlue : NSColor.systemBlue
        let boldColor = NSColor.textColor
        let codeColor = isDark ? NSColor.systemPink : NSColor.systemPink
        let codeBgColor = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.06)
        let linkColor = NSColor.systemBlue
        let commentColor = isDark ? NSColor.systemGray : NSColor.darkGray

        let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let monoFontBold = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let monoFontItalic: NSFont = {
            let descriptor = monoFont.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: 14) ?? monoFont
        }()

        // --- Fenced code blocks (``` ... ```) ---
        let codeBlockPattern = "(?m)^(`{3,})[^`]*$[\\s\\S]*?^\\1\\s*$"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: codeColor,
                    .backgroundColor: codeBgColor,
                ], range: match.range)
            }
        }

        // --- Headers (# ... ######) ---
        let headerPattern = "(?m)^(#{1,6})\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: headerPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let hashRange = match.range(at: 1)
                let level = hashRange.length
                let fontSize: CGFloat = max(14, 24 - CGFloat(level) * 2)
                let headerFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
                textStorage.addAttributes([
                    .font: headerFont,
                    .foregroundColor: headingColor,
                ], range: match.range)
            }
        }

        // --- Bold (**text** or __text__) ---
        let boldPattern = "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1"
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .font: monoFontBold,
                    .foregroundColor: boldColor,
                ], range: match.range)
            }
        }

        // --- Italic (*text* or _text_) - avoid matching ** ---
        let italicPattern = "(?<!\\*)(\\*|_)(?!\\1)(?=\\S)(.+?)(?<=\\S)\\1(?!\\1)"
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .font: monoFontItalic,
                ], range: match.range)
            }
        }

        // --- Inline code (`code`) ---
        let inlineCodePattern = "(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: codeColor,
                    .backgroundColor: codeBgColor,
                ], range: match.range)
            }
        }

        // --- Links [text](url) ---
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: match.range)
            }
        }

        // --- Blockquotes (> ...) ---
        let blockquotePattern = "(?m)^>\\s+(.*)$"
        if let regex = try? NSRegularExpression(pattern: blockquotePattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: commentColor,
                ], range: match.range)
            }
        }

        // --- List markers (- or * or numbered) ---
        let listPattern = "(?m)^(\\s*)([-*+]|\\d+\\.)\\s"
        if let regex = try? NSRegularExpression(pattern: listPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: headingColor,
                ], range: match.range(at: 2))
            }
        }

        // --- Horizontal rules (--- or *** or ___) ---
        let hrPattern = "(?m)^([-*_]{3,})\\s*$"
        if let regex = try? NSRegularExpression(pattern: hrPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: commentColor,
                ], range: match.range)
            }
        }
    }
}

// MARK: - Line Number Ruler View

class LineNumberRulerView: NSRulerView {
    private weak var associatedTextView: NSTextView?
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let lineNumberColor = NSColor.secondaryLabelColor

    init(textView: NSTextView) {
        self.associatedTextView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView

        // Observe text changes to redraw
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = associatedTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let text = textView.string as NSString
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count line number of first visible character
        var lineNumber = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        // Draw line numbers for visible lines
        let yOffset = textView.textContainerInset.height - visibleRect.origin.y
        var index = charRange.location

        while index < NSMaxRange(charRange) {
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 0), actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil)
            lineRect.origin.y += yOffset

            let attrs: [NSAttributedString.Key: Any] = [
                .font: lineNumberFont,
                .foregroundColor: lineNumberColor,
            ]
            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - 8,
                y: lineRect.origin.y + (lineRect.height - strSize.height) / 2
            )
            lineStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1

            // Move to next line
            var nextIndex = NSMaxRange(layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 0), actualCharacterRange: nil), actualGlyphRange: nil))

            // Find the actual end of the current visual line
            let lineRange = (textView.string as NSString).lineRange(for: NSRange(location: index, length: 0))
            nextIndex = NSMaxRange(lineRange)

            if nextIndex <= index {
                break
            }
            index = nextIndex
        }
    }
}
#endif
