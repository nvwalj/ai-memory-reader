import Foundation

/// On-disk copy of everything fetched from GitHub, so an added repository opens
/// instantly and keeps reading on a plane.
///
/// Blobs are stored by their git SHA rather than by path. Git already
/// content-addresses every file, so refreshing a repository only downloads what
/// actually changed, and a file that moved is a cache hit at its new path.
actor GitHubCache {
    static let shared = GitHubCache()

    private let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.root = base.appendingPathComponent("GitHubCache", isDirectory: true)
        }
    }

    // MARK: - Snapshot

    /// What a repository looked like the last time it was fetched.
    struct Snapshot: Codable, Sendable {
        var ref: String
        var info: GitHubRepoInfo
        var tree: GitHubTree
    }

    func snapshot(for repo: GitHubRepoRef) -> Snapshot? {
        let url = repoDirectory(repo).appendingPathComponent("snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func store(_ snapshot: Snapshot, for repo: GitHubRepoRef) {
        let directory = repoDirectory(repo)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    // MARK: - Blobs

    func blobText(sha: String) -> String? {
        guard let data = try? Data(contentsOf: blobURL(sha)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func storeBlob(_ text: String, sha: String) {
        let url = blobURL(sha)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Which of these blobs are already on disk — used to show how much of a
    /// repository is readable offline.
    func cachedBlobCount(shas: [String]) -> Int {
        shas.reduce(into: 0) { total, sha in
            if fm.fileExists(atPath: blobURL(sha).path(percentEncoded: false)) { total += 1 }
        }
    }

    // MARK: - Housekeeping

    func remove(_ repo: GitHubRepoRef) {
        try? fm.removeItem(at: repoDirectory(repo))
    }

    /// Total bytes on disk, for the Settings screen.
    func sizeOnDisk() -> Int64 {
        guard let walker = fm.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize
            total += Int64(size ?? 0)
        }
        return total
    }

    func clearAll() {
        try? fm.removeItem(at: root)
    }

    // MARK: - Paths

    /// Owner and repo names are URL-safe by GitHub's own rules, but they can
    /// contain `.` — so join them with a separator that can't appear in either.
    private func repoDirectory(_ repo: GitHubRepoRef) -> URL {
        root.appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("\(repo.owner)~\(repo.name)", isDirectory: true)
    }

    /// Sharded by the first two SHA characters, the way git itself does, so no
    /// single directory ends up with tens of thousands of entries.
    private func blobURL(_ sha: String) -> URL {
        let prefix = String(sha.prefix(2))
        let rest = String(sha.dropFirst(2))
        return root.appendingPathComponent("blobs", isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(rest.isEmpty ? sha : rest)
    }
}
