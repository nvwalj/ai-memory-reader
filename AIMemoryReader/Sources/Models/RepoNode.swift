import Foundation

/// A folder or document inside a repository listing.
///
/// The GitHub tree API returns a flat list of paths; this is the shape the
/// browser navigates. Unlike `FileNode` it has no URL, because nothing here is
/// on disk — a document is identified by its repo-relative path and fetched by
/// its blob SHA.
final class RepoNode: Identifiable, Hashable, @unchecked Sendable {
    /// Repo-relative path. `""` for the root.
    let path: String
    let name: String
    let isDirectory: Bool
    /// Git blob SHA — the cache key. Empty for directories.
    let sha: String
    let size: Int?
    private(set) var children: [RepoNode]

    var id: String { path.isEmpty ? "/" : path }

    init(path: String, name: String, isDirectory: Bool, sha: String = "", size: Int? = nil, children: [RepoNode] = []) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.sha = sha
        self.size = size
        self.children = children
    }

    var isJSON: Bool { ["json", "jsonl", "ndjson"].contains(ext) }
    var isMarkdown: Bool { ["md", "mdx", "mdc", "markdown", "mdown"].contains(ext) }
    var ext: String { (name as NSString).pathExtension.lowercased() }

    /// Every document at or below this node, in display order.
    var allFiles: [RepoNode] {
        isDirectory ? children.flatMap(\.allFiles) : [self]
    }

    func find(path target: String) -> RepoNode? {
        if path == target { return self }
        guard isDirectory else { return nil }
        // The tree is path-prefixed, so only descend where the answer can be.
        for child in children where target == child.path || target.hasPrefix(child.path + "/") {
            if let hit = child.find(path: target) { return hit }
        }
        return nil
    }

    static func == (lhs: RepoNode, rhs: RepoNode) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

enum RepoTreeBuilder {
    /// Turn a flat tree listing into a browsable hierarchy.
    ///
    /// Directories are derived from the surviving file paths rather than taken
    /// from the API's own `tree` entries, which prunes folders that hold nothing
    /// readable — the alternative is a repo whose listing is mostly empty
    /// `src/`, `node_modules/`, `.github/` chains you have to tap through.
    static func build(
        entries: [GitHubTreeEntry],
        subpath: String?,
        memoryFilesOnly: Bool
    ) -> RepoNode {
        let prefix: String = {
            guard let subpath, !subpath.isEmpty else { return "" }
            return subpath.hasSuffix("/") ? subpath : subpath + "/"
        }()

        let files = entries.filter { entry in
            guard entry.isFile else { return false }
            guard prefix.isEmpty || entry.path.hasPrefix(prefix) else { return false }
            return isBrowsable(entry.name, memoryFilesOnly: memoryFilesOnly)
        }

        let root = MutableFolder(path: prefix.isEmpty ? "" : String(prefix.dropLast()))
        for file in files {
            let relative = prefix.isEmpty ? file.path : String(file.path.dropFirst(prefix.count))
            var components = relative.split(separator: "/").map(String.init)
            guard let filename = components.popLast() else { continue }
            var folder = root
            var walked = root.path
            for component in components {
                walked = walked.isEmpty ? component : "\(walked)/\(component)"
                folder = folder.folder(named: component, path: walked)
            }
            folder.files.append(
                RepoNode(path: file.path, name: filename, isDirectory: false, sha: file.sha, size: file.size)
            )
        }
        return root.materialize(name: prefix.isEmpty ? "/" : (prefix.dropLast().split(separator: "/").last.map(String.init) ?? "/"))
    }

    /// Whether a filename is worth listing. `memoryFilesOnly` narrows to the same
    /// rule the macOS sidebar uses in strict mode.
    static func isBrowsable(_ filename: String, memoryFilesOnly: Bool) -> Bool {
        if memoryFilesOnly {
            return MemoryFileMatcher.isLikelyMemory(URL(fileURLWithPath: filename))
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        if FileNode.documentExtensions.contains(ext) { return true }
        // Extensionless conventions worth reading in a repo.
        return ["readme", "license", "changelog", "notice", "authors", "contributing"]
            .contains(filename.lowercased())
    }

    // MARK: - Building scaffold

    private final class MutableFolder {
        let path: String
        var files: [RepoNode] = []
        var folders: [String: MutableFolder] = [:]

        init(path: String) { self.path = path }

        func folder(named name: String, path: String) -> MutableFolder {
            if let existing = folders[name] { return existing }
            let created = MutableFolder(path: path)
            folders[name] = created
            return created
        }

        func materialize(name: String) -> RepoNode {
            let sortedFolders = folders
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map { $0.value.materialize(name: $0.key) }
            let sortedFiles = files
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return RepoNode(
                path: path,
                name: name,
                isDirectory: true,
                children: sortedFolders + sortedFiles
            )
        }
    }
}
