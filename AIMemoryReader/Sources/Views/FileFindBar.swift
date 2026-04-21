#if os(macOS)
import AppKit
import SwiftUI

// MARK: - FindMatch

/// One occurrence of the find query in the loaded document.
struct FindMatch: Identifiable, Equatable {
    let id: Int               // global ordinal, unique
    let sectionID: String     // MarkdownSection.id the hit lives in
    let lineNumber: Int       // 1-based line in the whole document
    let range: NSRange        // range in the raw document text
}

// MARK: - Compute matches for a document

enum FindMatcher {
    /// Scan `text` for all occurrences of `query` (case-insensitive).
    /// `sections` is used to tag each match with its owning section id so the
    /// read view can scroll to and highlight that section.
    static func compute(
        in text: String,
        query: String,
        sections: [MarkdownSection]
    ) -> [FindMatch] {
        guard !query.isEmpty, !text.isEmpty else { return [] }

        // Pre-compute absolute character range for each section.
        // Matches the splitter's behaviour: lines joined by "\n".
        var sectionStarts: [(id: String, start: Int, length: Int)] = []
        var cursor = 0
        for (i, section) in sections.enumerated() {
            let length = (section.content as NSString).length
            sectionStarts.append((section.id, cursor, length))
            cursor += length
            // MarkdownSplitter joins sections back with implicit "\n" between
            // lines within a section; between sections a newline separates them.
            if i < sections.count - 1 { cursor += 1 }
        }

        let ns = text as NSString
        var results: [FindMatch] = []
        var searchStart = 0
        var ordinal = 0

        while searchStart < ns.length {
            let remaining = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(of: query, options: .caseInsensitive, range: remaining)
            guard found.location != NSNotFound else { break }

            let lineNumber = lineNumberForLocation(found.location, in: ns)
            let sectionID = sectionIDContaining(location: found.location, in: sectionStarts)
                ?? sections.first?.id
                ?? "preamble"

            results.append(FindMatch(
                id: ordinal,
                sectionID: sectionID,
                lineNumber: lineNumber,
                range: found
            ))
            ordinal += 1
            // Advance; allow overlapping-insensitive by stepping past the match.
            searchStart = found.location + max(found.length, 1)
        }

        return results
    }

    private static func lineNumberForLocation(_ location: Int, in ns: NSString) -> Int {
        var count = 1
        let prefixRange = NSRange(location: 0, length: location)
        ns.enumerateSubstrings(in: prefixRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func sectionIDContaining(
        location: Int,
        in starts: [(id: String, start: Int, length: Int)]
    ) -> String? {
        for s in starts {
            if location >= s.start && location < s.start + s.length {
                return s.id
            }
        }
        // Location past last section → return the last one.
        return starts.last?.id
    }
}

// MARK: - FileFindBar

/// In-page find bar shown above the read view when ⌘F is pressed.
struct FileFindBar: View {
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int   // 0-based; ignored when matchCount == 0
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @Environment(\.themePalette) private var palette
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.isEyeCare ? palette.secondaryText : Color.secondary)
                .font(.system(size: 12))

            EscapableTextField(
                text: $query,
                placeholder: "Find in page…",
                onEscape: onClose,
                onSubmit: onNext,
                onSubmitReverse: onPrevious
            )
            .frame(minWidth: 200, maxWidth: 260)
            .focused($isFieldFocused)

            // Match counter
            Group {
                if query.isEmpty {
                    Text(" ")
                } else if matchCount == 0 {
                    Text("No matches")
                        .foregroundStyle(.red.opacity(0.85))
                } else {
                    Text("\(currentIndex + 1) of \(matchCount)")
                        .foregroundStyle(palette.isEyeCare ? palette.secondaryText : Color.secondary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .frame(minWidth: 80, alignment: .leading)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Previous match (⇧↩)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Next match (↩)")

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.isEyeCare ? palette.secondaryText : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            palette.isEyeCare
            ? AnyShapeStyle(palette.secondaryBackground)
            : AnyShapeStyle(.bar)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }
}

// MARK: - Escapable text field

/// A plain NSTextField wrapper that reports Esc & Return.
/// We need this because SwiftUI's TextField doesn't surface Esc.
struct EscapableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onEscape: () -> Void
    var onSubmit: () -> Void
    var onSubmitReverse: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = FindField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = NSFont.systemFont(ofSize: 12)
        field.stringValue = text
        field.isContinuous = true            // fire action on every keystroke
        field.target = context.coordinator
        field.action = #selector(Coordinator.textChangedAction(_:))
        // Separate action for Return — NSTextField sends action on Enter as well,
        // but with continuous+action we need a distinct hook for submit.
        field.cell?.sendsActionOnEndEditing = false
        field.onEscape = onEscape
        field.onSubmit = onSubmit
        field.onSubmitReverse = onSubmitReverse
        context.coordinator.onTextChanged = { [binding = _text] newValue in
            binding.wrappedValue = newValue
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let f = nsView as? FindField {
            f.onEscape = onEscape
            f.onSubmit = onSubmit
            f.onSubmitReverse = onSubmitReverse
        }
        context.coordinator.onTextChanged = { [binding = _text] newValue in
            binding.wrappedValue = newValue
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var onTextChanged: (String) -> Void = { _ in }

        @objc func textChangedAction(_ sender: NSTextField) {
            onTextChanged(sender.stringValue)
        }
    }

    /// NSTextField subclass that reports Esc, Return, and ⇧Return up to SwiftUI.
    final class FindField: NSTextField {
        var onEscape: (() -> Void)?
        var onSubmit: (() -> Void)?           // Return → next
        var onSubmitReverse: (() -> Void)?    // ⇧Return → previous

        override func cancelOperation(_ sender: Any?) {
            onEscape?()
        }

        override func textDidEndEditing(_ notification: Notification) {
            // Don't treat focus loss as submit — the keyDown override handles Return.
            super.textDidEndEditing(notification)
        }

        override func keyDown(with event: NSEvent) {
            // Return / Keypad-Enter: next (or previous when Shift is held)
            if event.keyCode == 36 || event.keyCode == 76 {
                if event.modifierFlags.contains(.shift) {
                    onSubmitReverse?()
                } else {
                    onSubmit?()
                }
                return
            }
            super.keyDown(with: event)
        }
    }
}
#endif
