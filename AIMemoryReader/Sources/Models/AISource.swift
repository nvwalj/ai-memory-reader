import SwiftUI

struct AISource: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String  // SF Symbol name
    let emoji: String?  // optional emoji to use instead of SF Symbol
    let color: Color
    let path: String  // relative to home directory

    var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
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
    static let allSources: [AISource] = [
        AISource(
            id: "openclaw",
            name: "OpenClaw",
            iconName: "brain.head.profile",
            emoji: "🦞",
            color: .orange,
            path: ".openclaw/workspace"
        ),
    ]

    static func detectAvailable() -> [AISource] {
        allSources.filter { $0.exists }
    }
}
