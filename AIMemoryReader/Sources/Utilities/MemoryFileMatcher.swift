import Foundation

/// Decides whether a file is plausibly an AI memory/config file (strict mode)
/// vs. just any JSON/YAML/Markdown the user happens to have.
///
/// Used to hide noise like `package.json`, `tsconfig.json`, etc. that appear
/// inside an AI tool's directory but aren't memory.
enum MemoryFileMatcher {
    /// Filenames recognized as AI memory/config even when their extension is generic.
    /// Matching is case-insensitive on the full filename.
    private static let knownFilenames: Set<String> = [
        // Continue
        "config.json",
        "config.yaml",
        "config.yml",
        // Cline / Roo Code (per-task storage)
        "ui_messages.json",
        "api_conversation_history.json",
        // Aider
        ".aider.conf.yml",
        ".aider.input.history",
        ".aider.chat.history.md",
        // Codex auto-memory consolidated views
        "memory_summary.md",
        // Claude Code projects
        "claude.md",
        "claude.local.md",
        // Cross-vendor open standard
        "agents.md",
        // Other vendor markdown
        "gemini.md",
        "copilot-instructions.md",
    ]

    /// Returns true if the file is plausibly an AI memory/config file.
    /// - Markdown-shaped extensions (`.md`, `.mdc`) are always allowed.
    /// - Newline-delimited JSON (`.jsonl`, `.ndjson`) is always allowed —
    ///   these are session transcripts in Claude Code, Codex, etc.
    /// - Generic `.json` / `.yaml` / `.yml` only allowed when the filename
    ///   is in the recognized set above.
    static func isLikelyMemory(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["md", "mdc", "jsonl", "ndjson"].contains(ext) { return true }
        if ["json", "yaml", "yml"].contains(ext) {
            return knownFilenames.contains(url.lastPathComponent.lowercased())
        }
        return false
    }
}
