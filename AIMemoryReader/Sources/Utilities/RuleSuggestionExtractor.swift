import Foundation

// MARK: - Model

struct RuleSuggestion: Identifiable, Hashable, Codable {
    let id: String  // stable hash of canonical form
    let text: String
    let frequency: Int
    let sessionIDs: [String]  // distinct sessions this appeared in
    let sourceID: String  // claude, codex, etc.

    var sessionCount: Int { sessionIDs.count }
}

// MARK: - Extractor

enum RuleSuggestionExtractor {

    /// Regex patterns that identify a user-typed correction to the model.
    /// Kept tight to avoid false positives in pasted code / Discord messages.
    private static let correctionPatterns: [NSRegularExpression] = {
        let raws = [
            // English starts-with corrections
            #"^(no|nope|wrong|stop|wait|actually|hold on)[\s,.!:]"#,
            #"\bdon'?t\s+(use|do|touch|edit|modify|change|add|create|run)"#,
            #"\binstead\s+of\b"#,
            #"\buse\s+\S+\s+not\s+\S+"#,
            #"^that's wrong"#,
            #"^that's not"#,
            // Chinese
            #"^(不对|错了|这不对|不是这样)"#,
            #"^(别|不要|不需要)\s*[^：:]"#,
            #"(应该用|改成|换成).+(不是|而不是)"#,
        ]
        return raws.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    /// Lines that should be ignored even if they match: Claude Code injects
    /// these meta tags into the user message stream, but they aren't real input.
    private static let metaTagPrefixes = [
        "<local-command", "<system-reminder", "<command-name>",
        "</command-name>", "<command-message", "<command-args",
        "<local-command-stdout>", "<channel "
    ]

    /// Stop-words used by the simple Jaccard clustering. Tiny set; we don't
    /// want to over-prune since corrections are short.
    private static let stopwords: Set<String> = [
        "the","a","an","is","are","was","were","be","to","of","in","on","at",
        "and","or","but","if","then","this","that","these","those",
        "i","you","we","they","it","my","your","our","their",
        "do","don't","dont","not","no",
        "请","和","是","在","了","的","也","就","和","跟"
    ]

    // MARK: Public entry

    /// Scan all `*.jsonl` under a source root (e.g. ~/.claude/projects/) and
    /// return clustered correction-style suggestions, ordered by frequency desc.
    /// Returns at most `limit` suggestions, each with `frequency >= minFrequency`.
    static func scan(
        sourceRoot: URL,
        sourceID: String,
        minFrequency: Int = 2,
        limit: Int = 50
    ) async -> [RuleSuggestion] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: sourceRoot.path(percentEncoded: false)) else {
                return []
            }
            // Walk for .jsonl files (Claude Code stores under projects/<path>/<session>.jsonl,
            // Codex under sessions/, so we just walk).
            var jsonlURLs: [URL] = []
            if let enumerator = fm.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                while let obj = enumerator.nextObject() {
                    if let url = obj as? URL, url.pathExtension.lowercased() == "jsonl" {
                        jsonlURLs.append(url)
                    }
                }
            }
            // Extract corrections per file
            var raw: [(text: String, sessionID: String)] = []
            for url in jsonlURLs {
                let sessionID = url.deletingPathExtension().lastPathComponent
                raw.append(contentsOf: Self.extractCorrections(from: url, sessionID: sessionID))
            }
            // Cluster
            let clusters = Self.cluster(corrections: raw)
            // Filter + sort
            return clusters
                .filter { $0.frequency >= minFrequency }
                .sorted { $0.frequency > $1.frequency }
                .prefix(limit)
                .map { $0.toSuggestion(sourceID: sourceID) }
        }.value
    }

    // MARK: Extraction (per file)

    private static func extractCorrections(from url: URL, sessionID: String) -> [(text: String, sessionID: String)] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [] }

        var out: [(String, String)] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            // We only care about "user" messages
            let type = obj["type"] as? String
            if type != "user" { continue }
            guard let message = obj["message"] as? [String: Any] else { continue }
            let text = Self.extractText(from: message)
            guard !text.isEmpty, text.count >= 5, text.count <= 500 else { continue }
            // Skip meta tags
            if Self.metaTagPrefixes.contains(where: { text.hasPrefix($0) || text.contains($0) }) { continue }
            // Match correction patterns
            if Self.isCorrection(text) {
                out.append((text.trimmingCharacters(in: .whitespacesAndNewlines), sessionID))
            }
        }
        return out
    }

    private static func extractText(from message: [String: Any]) -> String {
        if let s = message["content"] as? String { return s }
        guard let arr = message["content"] as? [[String: Any]] else { return "" }
        var combined = ""
        for item in arr where (item["type"] as? String) == "text" {
            if let t = item["text"] as? String { combined += t }
        }
        return combined
    }

    private static func isCorrection(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: text.utf16.count)
        for re in correctionPatterns {
            if re.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: Clustering

    /// Internal cluster shape with mutable accumulation, then converted to RuleSuggestion.
    private struct Cluster {
        var representative: String
        var sessions: Set<String>
        var frequency: Int

        func toSuggestion(sourceID: String) -> RuleSuggestion {
            RuleSuggestion(
                id: representative.normalizedFingerprint(),
                text: representative,
                frequency: frequency,
                sessionIDs: Array(sessions).sorted(),
                sourceID: sourceID
            )
        }
    }

    /// Simple Jaccard-similarity clustering. O(N²) over corrections — fine because
    /// real-world counts stay in the hundreds even after months of session log.
    private static func cluster(corrections: [(text: String, sessionID: String)]) -> [Cluster] {
        var clusters: [Cluster] = []
        for (text, sid) in corrections {
            let tokens = tokenize(text)
            guard !tokens.isEmpty else { continue }
            var merged = false
            for idx in clusters.indices {
                let repTokens = tokenize(clusters[idx].representative)
                if jaccard(tokens, repTokens) >= 0.55 {
                    clusters[idx].frequency += 1
                    clusters[idx].sessions.insert(sid)
                    // Keep the shorter representative (usually crisper)
                    if text.count < clusters[idx].representative.count {
                        clusters[idx].representative = text
                    }
                    merged = true
                    break
                }
            }
            if !merged {
                clusters.append(Cluster(
                    representative: text,
                    sessions: [sid],
                    frequency: 1
                ))
            }
        }
        return clusters
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        let chars = lower.unicodeScalars
        var tokens: Set<String> = []
        var current = ""
        for ch in chars {
            if CharacterSet.alphanumerics.contains(ch) {
                current.unicodeScalars.append(ch)
            } else {
                if current.count >= 2 && !stopwords.contains(current) {
                    tokens.insert(current)
                }
                current = ""
            }
        }
        if current.count >= 2 && !stopwords.contains(current) {
            tokens.insert(current)
        }
        return tokens
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

// MARK: - Helpers

private extension String {
    /// Stable id derived from normalized text — collapses whitespace + case
    /// so the same suggestion text always hashes to the same id across runs.
    func normalizedFingerprint() -> String {
        let normalized = self.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Simple djb2 hash so id is short + stable. Suggestion text is the
        // human-readable surface; this id is only used for SwiftUI identity.
        var hash: UInt64 = 5381
        for ch in normalized.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(ch)
        }
        return String(hash, radix: 36)
    }
}
