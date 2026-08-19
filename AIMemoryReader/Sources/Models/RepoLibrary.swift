import Foundation

/// The repositories the user has added, in the order they appear on the home screen.
@MainActor
@Observable
final class RepoLibrary {
    private(set) var repos: [GitHubRepoRef]
    private(set) var isAdding = false
    var addError: String?

    /// Narrow every repository's listing to files that look like AI memory/config.
    var memoryFilesOnly: Bool {
        didSet {
            guard oldValue != memoryFilesOnly else { return }
            SettingsStore.shared.githubMemoryFilesOnly = memoryFilesOnly
            for session in sessions.values { session.rebuild(memoryFilesOnly: memoryFilesOnly) }
        }
    }

    /// One session per repository, kept alive so re-entering a repo is instant.
    private var sessions: [String: RepoSession] = [:]

    init() {
        repos = SettingsStore.shared.githubRepos
        memoryFilesOnly = SettingsStore.shared.githubMemoryFilesOnly
    }

    func session(for repo: GitHubRepoRef) -> RepoSession {
        if let existing = sessions[repo.id] { return existing }
        let created = RepoSession(repo: repo, memoryFilesOnly: memoryFilesOnly)
        sessions[repo.id] = created
        return created
    }

    // MARK: - Mutating the list

    /// Resolve what the user typed and add it. Returns the added repo, or nil
    /// with `addError` set — the caller keeps the sheet open in that case.
    @discardableResult
    func add(_ input: String) async -> GitHubRepoRef? {
        addError = nil
        guard var repo = GitHubRepoRef.parse(input) else {
            addError = "That doesn't look like a GitHub repository. Try owner/repo or a github.com link."
            return nil
        }
        guard !repos.contains(where: { $0.id == repo.id }) else {
            addError = "\(repo.slug) is already in your list."
            return nil
        }

        isAdding = true
        defer { isAdding = false }

        let client = GitHubClient(token: GitHubTokenStore.token)
        do {
            // Validates the repo exists and is readable before it lands in the
            // list, so a typo doesn't become a permanently broken row.
            let info = try await client.repositoryInfo(repo)
            if repo.ref == nil { repo.ref = info.defaultBranch }
            let tree = try await client.tree(repo, ref: repo.ref ?? info.defaultBranch)
            await GitHubCache.shared.store(
                GitHubCache.Snapshot(ref: repo.ref ?? info.defaultBranch, info: info, tree: tree),
                for: repo
            )
            repos.insert(repo, at: 0)
            persist()
            // Seed the session so opening the row shows the tree immediately.
            let session = RepoSession(repo: repo, memoryFilesOnly: memoryFilesOnly)
            session.adopt(info: info, tree: tree, fromCache: false)
            sessions[repo.id] = session
            return repo
        } catch is CancellationError {
            return nil
        } catch {
            addError = (error as? GitHubError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func remove(_ repo: GitHubRepoRef) {
        repos.removeAll { $0.id == repo.id }
        sessions[repo.id] = nil
        persist()
        Task { await GitHubCache.shared.remove(repo) }
    }

    func remove(atOffsets offsets: IndexSet) {
        for index in offsets { remove(repos[index]) }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        repos.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    private func persist() {
        SettingsStore.shared.githubRepos = repos
    }
}

/// Load state for one repository's listing.
@MainActor
@Observable
final class RepoSession {
    enum Status: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let repo: GitHubRepoRef
    private(set) var status: Status = .idle
    private(set) var root: RepoNode?
    private(set) var info: GitHubRepoInfo?
    private(set) var tree: GitHubTree?
    private(set) var isRefreshing = false
    /// Non-fatal thing the user should know: showing a stale copy, or a listing
    /// GitHub had to cut short.
    private(set) var warning: String?

    /// A heading the next document should scroll to once it has parsed its own
    /// headings. Carries the path because the jump is requested from the document
    /// being *left*, which must not consume it itself.
    var pendingHeading: (path: String, heading: String)?

    private var memoryFilesOnly: Bool
    private var didLoadOnce = false

    init(repo: GitHubRepoRef, memoryFilesOnly: Bool) {
        self.repo = repo
        self.memoryFilesOnly = memoryFilesOnly
    }

    var resolvedRef: String { repo.ref ?? info?.defaultBranch ?? "HEAD" }

    var fileCount: Int { root?.allFiles.count ?? 0 }

    // MARK: - Loading

    /// Show the cached listing first and refresh behind it. A repo you've opened
    /// before should never make you wait on the network, and should still open
    /// with no network at all.
    func load(force: Bool = false) async {
        if didLoadOnce && !force { return }

        if root == nil, let cached = await GitHubCache.shared.snapshot(for: repo) {
            adopt(info: cached.info, tree: cached.tree, fromCache: true)
        }

        // `didLoadOnce` is set by a refresh that actually finished. Setting it up
        // front would strand the session on its cached copy forever, because the
        // very first load is the one most likely to be cancelled — SwiftUI tears
        // down the row's `.task` the moment you navigate into the repository.
        await refresh(silent: root != nil)
    }

    func refresh(silent: Bool = false) async {
        if !silent { status = .loading }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = GitHubClient(token: GitHubTokenStore.token)
        do {
            var resolved = repo.ref
            var repoInfo = info
            if resolved == nil || repoInfo == nil {
                repoInfo = try await client.repositoryInfo(repo)
                resolved = resolved ?? repoInfo?.defaultBranch
            }
            guard let ref = resolved, let repoInfo else {
                throw GitHubError.notFound(repo.slug)
            }
            let fetched = try await client.tree(repo, ref: ref)
            adopt(info: repoInfo, tree: fetched, fromCache: false)
            didLoadOnce = true
            await GitHubCache.shared.store(
                GitHubCache.Snapshot(ref: ref, info: repoInfo, tree: fetched),
                for: repo
            )
        } catch is CancellationError {
            // The view went away mid-request. Nothing to report, and nothing to
            // remember — the next appearance retries.
            return
        } catch {
            if Task.isCancelled { return }
            let message = (error as? GitHubError)?.errorDescription ?? error.localizedDescription
            if root != nil {
                // A stale listing beats an error screen — say it's stale instead.
                warning = "Showing the saved copy — \(message)"
            } else {
                status = .failed(message)
            }
        }
    }

    func adopt(info: GitHubRepoInfo, tree: GitHubTree, fromCache: Bool) {
        self.info = info
        self.tree = tree
        self.root = RepoTreeBuilder.build(
            entries: tree.entries, subpath: repo.subpath, memoryFilesOnly: memoryFilesOnly
        )
        self.status = .ready
        self.warning = tree.truncated ? GitHubError.truncatedTree.errorDescription : nil
        if fromCache, warning == nil {
            let age = Date().timeIntervalSince(tree.fetchedAt)
            if age > 60 * 60 * 24 { warning = "Saved copy from \(Self.relative(tree.fetchedAt))." }
        }
    }

    func rebuild(memoryFilesOnly: Bool) {
        self.memoryFilesOnly = memoryFilesOnly
        guard let tree else { return }
        root = RepoTreeBuilder.build(
            entries: tree.entries, subpath: repo.subpath, memoryFilesOnly: memoryFilesOnly
        )
    }

    // MARK: - Documents

    /// Cache-first by blob SHA. Git already content-addresses files, so an
    /// unchanged document never downloads twice, no matter how often the branch
    /// moves under it.
    func documentText(for node: RepoNode) async throws -> String {
        if let cached = await GitHubCache.shared.blobText(sha: node.sha) {
            return cached
        }
        let client = GitHubClient(token: GitHubTokenStore.token)
        let text = try await client.fileText(
            repo, ref: resolvedRef, path: node.path, knownSize: node.size
        )
        await GitHubCache.shared.storeBlob(text, sha: node.sha)
        return text
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
