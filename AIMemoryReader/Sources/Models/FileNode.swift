import Foundation

@Observable
final class FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?
    var isExpanded: Bool = false

    /// All file extensions that *could* be AI-related.
    /// Used in the "show all" mode. Strict mode uses MemoryFileMatcher.
    static let supportedExtensions: Set<String> = ["md", "mdx", "mdc", "json", "jsonl", "ndjson", "yaml", "yml"]

    /// Everything the reader can display. Wider than `supportedExtensions`,
    /// which exists to keep a *local AI tool directory* free of noise; a GitHub
    /// repository is browsed for its documents, so plain text and `.markdown`
    /// belong too.
    static let documentExtensions: Set<String> =
        supportedExtensions.union(["markdown", "mdown", "txt", "text", "toml"])

    var isMarkdown: Bool { ["md", "mdx", "mdc"].contains(url.pathExtension.lowercased()) }
    var isJSON: Bool { ["json", "jsonl", "ndjson"].contains(url.pathExtension.lowercased()) }

    /// In strict mode only known memory/config files pass.
    /// In loose mode (default) any of `supportedExtensions` passes —
    /// used when the user explicitly opens a file (drag-drop, picker).
    static func isSupportedFile(_ url: URL, strict: Bool = false) -> Bool {
        if strict {
            return MemoryFileMatcher.isLikelyMemory(url)
        }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = url.path(percentEncoded: false)
        self.name = url.lastPathComponent
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
