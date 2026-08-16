import Foundation

/// Rewrites `[[wiki links]]` into ordinary markdown links so the renderer makes
/// them clickable.
///
/// Claude Code's memory files cross-reference each other with `[[name]]`, and
/// Obsidian vaults use the same syntax. CommonMark has no notion of it, so both
/// render as literal brackets — visibly a link, but dead. Rewriting to
/// `[name](name)` hands them to the normal link path, where `LinkResolver`
/// matches the slug against the file on disk.
///
/// The rewrite is display-only. The editor and the save path keep the file's
/// real text, so opening a memory in edit mode still shows `[[name]]`.
enum WikiLinkRewriter {
    static func rewrite(_ markdown: String) -> String {
        // Cheap bail-out — most files have none.
        guard markdown.contains("[[") else { return markdown }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var rewritten: [String] = []
        rewritten.reserveCapacity(lines.count)
        var inFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                rewritten.append(String(line))
                continue
            }
            rewritten.append(inFence ? String(line) : rewriteLine(String(line)))
        }

        // One element per line in, one out — joining restores the original
        // line endings exactly, trailing newline included.
        return rewritten.joined(separator: "\n")
    }

    // MARK: - Line scanning

    private static func rewriteLine(_ line: String) -> String {
        var out = String()
        out.reserveCapacity(line.count)
        var i = line.startIndex
        var inCode = false

        while i < line.endIndex {
            let c = line[i]

            // Inline code spans are literal — `[[not a link]]` inside backticks
            // is text about the syntax, not a use of it.
            if c == "`" {
                inCode.toggle()
                out.append(c)
                i = line.index(after: i)
                continue
            }

            if !inCode, c == "[", let body = wikiBody(in: line, startingAt: i) {
                out += markdownLink(for: body.text)
                i = body.end
                continue
            }

            out.append(c)
            i = line.index(after: i)
        }
        return out
    }

    /// If `line` has `[[…]]` starting at `start`, return its inner text and the
    /// index just past the closing brackets.
    private static func wikiBody(in line: String, startingAt start: String.Index)
        -> (text: String, end: String.Index)? {
        let afterFirst = line.index(after: start)
        guard afterFirst < line.endIndex, line[afterFirst] == "[" else { return nil }
        let bodyStart = line.index(after: afterFirst)
        guard bodyStart < line.endIndex else { return nil }

        var i = bodyStart
        while let close = line[i...].firstIndex(of: "]") {
            let afterClose = line.index(after: close)
            guard afterClose < line.endIndex, line[afterClose] == "]" else {
                // A single `]` — keep looking for the real `]]`.
                guard afterClose < line.endIndex else { return nil }
                i = afterClose
                continue
            }
            let text = String(line[bodyStart..<close])
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (text, line.index(after: afterClose))
        }
        return nil
    }

    // MARK: - Emitting

    /// `[[target]]` → `[target](target)`, `[[target|label]]` → `[label](target)`.
    private static func markdownLink(for body: String) -> String {
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let target = parts[0].trimmingCharacters(in: .whitespaces)
        let label = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : target
        guard !target.isEmpty else { return "[[\(body)]]" }
        return "[\(escapeLabel(label.isEmpty ? target : label))](\(encodeTarget(target)))"
    }

    /// Percent-encode the destination, but keep `#` literal so `[[note#section]]`
    /// still arrives at the resolver as a path plus an anchor.
    private static func encodeTarget(_ target: String) -> String {
        let allowed = CharacterSet.urlPathAllowed
        return target
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "#")
    }

    /// Brackets and parens inside the label would end the link early.
    private static func escapeLabel(_ label: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(label.count)
        for c in label {
            if c == "[" || c == "]" || c == "(" || c == ")" { escaped.append("\\") }
            escaped.append(c)
        }
        return escaped
    }
}
