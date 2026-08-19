import Foundation

/// The display-only transformations applied between the bytes on disk and the
/// renderer.
///
/// Everything here is reversible-by-omission: the raw text is what edit mode
/// shows and what gets saved, so a rewrite can improve reading without ever
/// touching the file.
enum MarkdownDisplayPrep {
    static func prepare(_ markdown: String) -> String {
        WikiLinkRewriter.rewrite(stripHTMLComments(markdown))
    }

    /// Remove `<!-- … -->`, which CommonMark passes through as raw HTML and
    /// MarkdownUI then draws as literal text. Every other Markdown surface —
    /// GitHub included — hides comments, and AI memory files use them for notes
    /// addressed to agents rather than to the reader.
    ///
    /// Fenced blocks are left alone: a document explaining the syntax must still
    /// be able to show it.
    static func stripHTMLComments(_ markdown: String) -> String {
        guard markdown.contains("<!--") else { return markdown }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        output.reserveCapacity(lines.count)
        var inFence = false
        var inComment = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inComment, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                continue
            }
            if inFence {
                output.append(line)
                continue
            }

            if inComment {
                // Inside a multi-line comment: drop everything up to the close.
                if let end = line.range(of: "-->") {
                    inComment = false
                    let rest = String(line[end.upperBound...])
                    let cleaned = stripInline(rest, inComment: &inComment)
                    if !cleaned.trimmingCharacters(in: .whitespaces).isEmpty { output.append(cleaned) }
                }
                continue
            }

            let cleaned = stripInline(line, inComment: &inComment)
            // A line that was *only* a comment disappears entirely rather than
            // leaving a blank that changes the paragraph structure around it.
            if cleaned.trimmingCharacters(in: .whitespaces).isEmpty
                && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            output.append(cleaned)
        }
        return output.joined(separator: "\n")
    }

    /// Strip every complete `<!-- … -->` on one line. An unterminated opener sets
    /// `inComment` so the caller keeps swallowing lines.
    private static func stripInline(_ line: String, inComment: inout Bool) -> String {
        var result = line
        while let open = result.range(of: "<!--") {
            if let close = result.range(of: "-->", range: open.upperBound..<result.endIndex) {
                result.replaceSubrange(open.lowerBound..<close.upperBound, with: "")
            } else {
                result = String(result[result.startIndex..<open.lowerBound])
                inComment = true
                break
            }
        }
        return result
    }
}
