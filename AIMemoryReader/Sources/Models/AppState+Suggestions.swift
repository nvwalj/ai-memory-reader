import Foundation

// MARK: - Suggested Rules state + actions

@MainActor
extension AppState {
    /// Persistently-dismissed suggestion IDs (UserDefaults-backed).
    /// Once dismissed, a suggestion won't reappear even after re-scan.
    var dismissedSuggestionIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.dismissedKey)
        }
    }

    private static let dismissedKey = "AIMR.suggestedRules.dismissed"

    // MARK: Actions

    /// Re-scan the currently selected AI source's session logs for repeated
    /// corrections. Updates `suggestedRules`.
    func refreshSuggestedRules() async {
        guard let sourceID = selectedSourceID,
              let source = availableSources.first(where: { $0.id == sourceID }) else {
            suggestedRules = []
            return
        }
        let url = source.url
        let id = source.id
        let results = await RuleSuggestionExtractor.scan(
            sourceRoot: url,
            sourceID: id
        )
        suggestedRules = results
    }

    /// Dismiss a suggestion — adds its id to the persisted set.
    func dismissSuggestion(_ suggestion: RuleSuggestion) {
        var current = dismissedSuggestionIDs
        current.insert(suggestion.id)
        dismissedSuggestionIDs = current
    }

    /// Append the suggestion text as a bullet to the most relevant CLAUDE.md.
    /// Strategy: for Claude Code source, target `~/.claude/CLAUDE.md` (global).
    /// For other sources, target their conventional global file (`AGENTS.md` for Codex, etc.).
    /// Best-effort; if no target found, append to the source's root + `CLAUDE.md`.
    func addSuggestionToClaudeMd(_ suggestion: RuleSuggestion) {
        guard let source = availableSources.first(where: { $0.id == suggestion.sourceID }) else {
            return
        }
        let target = targetMemoryFile(for: source)
        appendRule(suggestion.text, to: target)
        // Once promoted, dismiss it so it doesn't reappear.
        dismissSuggestion(suggestion)
    }

    private func targetMemoryFile(for source: AISource) -> URL {
        let base = source.url
        let filename: String
        switch source.id {
        case "codex":   filename = "AGENTS.md"
        case "gemini":  filename = "GEMINI.md"
        case "openclaw": filename = "CLAW.md"
        case "aider":   filename = "CONVENTIONS.md"
        default:        filename = "CLAUDE.md"
        }
        return base.appendingPathComponent(filename)
    }

    private func appendRule(_ text: String, to fileURL: URL) {
        let fm = FileManager.default
        let path = fileURL.path(percentEncoded: false)
        let header = "\n\n## Promoted from session logs\n\n"
        let bullet = "- " + text + "\n"

        if fm.fileExists(atPath: path) {
            // Read existing, check if header already present
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let toAppend: String
            if existing.contains("## Promoted from session logs") {
                toAppend = bullet
            } else {
                toAppend = header + bullet
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(toAppend.utf8))
                try? handle.close()
            }
        } else {
            // Create with header
            let body = "# AI agent memory\n" + header + bullet
            try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}

