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
        // On iOS, sources aren't filesystem-based — fall back to a sentinel if the docs dir is unavailable.
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: "/dev/null")
        }
        return docs.appendingPathComponent(path)
        #endif
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Check if directory contains at least one supported file (recursive, shallow check)
    var containsSupportedFiles: Bool {
        let fm = FileManager.default
        let dirPath = url.path(percentEncoded: false)
        guard let enumerator = fm.enumerator(atPath: dirPath) else { return false }
        while let file = enumerator.nextObject() as? String {
            let ext = (file as NSString).pathExtension.lowercased()
            if FileNode.supportedExtensions.contains(ext) {
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
            id: "claude",
            name: "Claude Code",
            iconName: "terminal",
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
            iconName: "terminal",
            color: .blue,
            path: ".gemini"
        ),
        AISource(
            id: "cursor",
            name: "Cursor",
            iconName: "terminal",
            color: .cyan,
            path: ".cursor"
        ),
        AISource(
            id: "continue",
            name: "Continue",
            iconName: "terminal",
            color: .purple,
            path: ".continue"
        ),
        AISource(
            id: "copilot",
            name: "GitHub Copilot",
            iconName: "terminal",
            color: Color(white: 0.35),
            path: ".config/github-copilot"
        ),
        AISource(
            id: "aider",
            name: "Aider",
            iconName: "terminal",
            color: .gray,
            path: ".aider"
        ),
        AISource(
            id: "openclaw",
            name: "OpenClaw",
            iconName: "terminal",
            color: .orange,
            path: ".openclaw/workspace"
        ),
    ]

    /// Detect auto-discovered sources that exist and contain supported files
    static func detectAvailable() -> [AISource] {
        #if os(iOS)
        return []
        #else
        return allSources.filter { $0.exists && $0.containsSupportedFiles }
        #endif
    }

    // MARK: - Custom sources (UserDefaults)

    /// Load custom source paths from SettingsStore (iCloud synced)
    static func loadCustomSources() -> [AISource] {
        let paths = SettingsStore.shared.customAISourcePaths
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
        var paths = SettingsStore.shared.customAISourcePaths
        guard !paths.contains(path) else { return }
        paths.append(path)
        SettingsStore.shared.customAISourcePaths = paths
    }

    /// Remove a custom source path
    static func removeCustomSource(path: String) {
        var paths = SettingsStore.shared.customAISourcePaths
        paths.removeAll { $0 == path }
        SettingsStore.shared.customAISourcePaths = paths
    }

    /// All available sources: auto-detected + custom
    static func detectAllAvailable() -> [AISource] {
        let autoDetected = detectAvailable()
        let custom = loadCustomSources()
        return autoDetected + custom
    }
}
