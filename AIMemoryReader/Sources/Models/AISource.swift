import SwiftUI

struct AISource: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String  // SF Symbol name
    let emoji: String?  // optional emoji to use instead of SF Symbol
    let color: Color
    let path: String  // relative to home directory, or absolute for custom sources
    let isCustom: Bool

    init(id: String, name: String, iconName: String, emoji: String? = nil, color: Color, path: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.emoji = emoji
        self.color = color
        self.path = path
        self.isCustom = isCustom
    }

    var url: URL {
        #if os(macOS)
        if isCustom || path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        #else
        // On iOS, sources aren't filesystem-based
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(path)
        #endif
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Check if directory contains at least one .md file (recursive, shallow check)
    var containsMarkdownFiles: Bool {
        let fm = FileManager.default
        let dirPath = url.path(percentEncoded: false)
        guard let enumerator = fm.enumerator(atPath: dirPath) else { return false }
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".md") {
                return true
            }
        }
        return false
    }

    /// Returns today's memory file URL if it exists (memory/YYYY-MM-DD.md)
    var todayMemoryFile: URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayName = formatter.string(from: Date())
        let memoryURL = url.appendingPathComponent("memory/\(todayName).md")
        if FileManager.default.fileExists(atPath: memoryURL.path(percentEncoded: false)) {
            return memoryURL
        }
        return nil
    }
}

extension AISource {
    // MARK: - Auto-detected sources

    static let allSources: [AISource] = [
        AISource(
            id: "openclaw",
            name: "OpenClaw",
            iconName: "ant",
            color: .orange,
            path: ".openclaw/workspace"
        ),
        AISource(
            id: "claude",
            name: "Claude Code",
            iconName: "chevron.left.forwardslash.chevron.right",
            color: Color(red: 0.76, green: 0.55, blue: 0.25),
            path: ".claude"
        ),
        AISource(
            id: "codex",
            name: "Codex",
            iconName: "terminal",
            color: .green,
            path: ".codex"
        ),
        AISource(
            id: "gemini",
            name: "Gemini",
            iconName: "sparkles",
            color: .blue,
            path: ".gemini"
        ),
        AISource(
            id: "continue",
            name: "Continue",
            iconName: "play.circle",
            color: .purple,
            path: ".continue"
        ),
        AISource(
            id: "cursor",
            name: "Cursor",
            iconName: "cursorarrow.rays",
            color: .cyan,
            path: ".cursor"
        ),
        AISource(
            id: "aider",
            name: "Aider",
            iconName: "wrench",
            color: .gray,
            path: ".aider"
        ),
        AISource(
            id: "copilot",
            name: "GitHub Copilot",
            iconName: "airplane",
            color: Color(white: 0.35),
            path: ".config/github-copilot"
        ),
    ]

    /// Detect auto-discovered sources that exist and contain .md files
    static func detectAvailable() -> [AISource] {
        #if os(iOS)
        return []
        #else
        return allSources.filter { $0.exists && $0.containsMarkdownFiles }
        #endif
    }

    // MARK: - Custom sources (UserDefaults)

    private static let customSourcesKey = "customAISourcePaths"

    /// Load custom source paths from UserDefaults
    static func loadCustomSources() -> [AISource] {
        let paths = UserDefaults.standard.stringArray(forKey: customSourcesKey) ?? []
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return AISource(
                id: "custom:\(path)",
                name: url.lastPathComponent,
                iconName: "folder",
                color: .secondary,
                path: path,
                isCustom: true
            )
        }
    }

    /// Add a custom source path
    static func addCustomSource(path: String) {
        var paths = UserDefaults.standard.stringArray(forKey: customSourcesKey) ?? []
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: customSourcesKey)
    }

    /// Remove a custom source path
    static func removeCustomSource(path: String) {
        var paths = UserDefaults.standard.stringArray(forKey: customSourcesKey) ?? []
        paths.removeAll { $0 == path }
        UserDefaults.standard.set(paths, forKey: customSourcesKey)
    }

    /// All available sources: auto-detected + custom
    static func detectAllAvailable() -> [AISource] {
        let autoDetected = detectAvailable()
        let custom = loadCustomSources()
        return autoDetected + custom
    }
}
