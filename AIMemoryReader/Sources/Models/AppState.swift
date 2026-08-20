import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var rootNode: FileNode?
    var rootURL: URL?

    /// Every path into a file funnels through here — sidebar clicks, search
    /// hits, and links inside a document — so the back/forward stacks below
    /// only have to watch this one property.
    var selectedFile: FileNode? {
        didSet {
            guard !isRestoringHistory, oldValue != selectedFile else { return }
            if let oldValue {
                backStack.append(oldValue)
                if backStack.count > Self.historyLimit {
                    backStack.removeFirst(backStack.count - Self.historyLimit)
                }
            }
            forwardStack.removeAll()
        }
    }

    /// When true, a single file was opened directly (not a directory)
    var isSingleFileMode: Bool = false

    /// True while a directory tree is being scanned off the main actor. The
    /// scan of a large folder can take a moment; the sidebar shows progress
    /// instead of an empty tree it can't explain.
    var isLoadingTree: Bool = false

    /// The in-flight tree scan, cancelled whenever a new one starts so we never
    /// pay for a walk whose result is already stale.
    private var treeLoadTask: Task<Void, Never>?

    var availableSources: [AISource] = []

    /// True until the first asynchronous source detection finishes. Used to
    /// suppress the "grant access" empty state from flashing before detection
    /// has had a chance to populate `availableSources`.
    var isDetectingSources: Bool = true
    private var didStartDetection = false

    var selectedSourceID: String? {
        didSet {
            SettingsStore.shared.lastSelectedSourceID = selectedSourceID
        }
    }

    /// Today's memory file node, if the current source has one
    var todayFileNode: FileNode?

    // MARK: - Search

    var searchQuery: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var focusSearch: Bool = false

    // MARK: - Appearance

    var appTheme: AppTheme = .standard {
        didSet {
            SettingsStore.shared.appThemeRaw = appTheme.rawValue
        }
    }

    /// Toggle in View menu. When false (default), only known AI memory files show.
    /// When true, every .json/.jsonl/.md/.mdc/.yaml under the source is listed.
    var showAllJsonFiles: Bool = false {
        didSet {
            guard oldValue != showAllJsonFiles else { return }
            SettingsStore.shared.showAllJsonFiles = showAllJsonFiles
            rebuildCurrentTree()
        }
    }

    // MARK: - In-page Find

    /// Pulsed to request the Detail view open its find-in-file bar.
    /// DetailView observes and becomes active when a file is loaded.
    var findInFileToken: Int = 0

    // MARK: - File Watching

    #if os(macOS)
    private var activeStream: FSEventStreamRef?
    private var fsObserver: Any?
    private var debounceTask: Task<Void, Never>?
    private var debounceStartedAt: Date?
    private var lastReloadSignal: Date = .distantPast
    #endif

    /// Incremented on each file-system change so views can react.
    ///
    /// The detail view uses it to re-check whether the file it is showing has
    /// changed underneath — **not** to reload it. Text that rewrites itself
    /// while you are reading is worse than text that is briefly out of date, so
    /// the reload is always the reader's decision (⌘R).
    var fileChangeToken: Int = 0

    /// Pulsed by "Reload from Disk" (⌘R). Separate from `fileChangeToken`: that
    /// one is skipped while editing, because a reload mid-edit would throw the
    /// edit away, whereas an explicit reload is something the user asked for and
    /// saves first.
    var reloadToken: Int = 0

    func requestReload() {
        reloadToken &+= 1
    }

    // MARK: - Suggested Rules (v0.5)
    /// Cached scan results, sorted by frequency desc.
    var suggestedRules: [RuleSuggestion] = []
    /// Controls the Suggested Rules sheet visibility.
    var showSuggestedRulesSheet: Bool = false

    // MARK: - Recent Items

    /// Recently opened files and folders (most-recent first), shown in the sidebar "Recent" list.
    var recentItems: [String] {
        get { SettingsStore.shared.recentItems }
        set { SettingsStore.shared.recentItems = newValue }
    }

    // MARK: - URL Scheme handling

    var pendingURLPath: String?

    /// A heading the detail view should scroll to once `filePath` is on screen.
    /// Carrying the path matters: the jump is requested before the target file
    /// has parsed its headings, and the view that's still showing the *old*
    /// file must not swallow the request.
    struct PendingHeading: Equatable {
        let filePath: String
        let heading: String
    }

    var pendingHeading: PendingHeading?

    /// A `aimemoryreader://repo?…` link waiting for the iOS shell to turn it into
    /// a navigation path. Parsed here so the URL grammar lives in one place, but
    /// acted on there, because only that layer owns the repository list.
    struct RepoDeepLink: Equatable {
        var repo: GitHubRepoRef
        var documentPath: String?
        var heading: String?
    }

    var pendingRepoLink: RepoDeepLink?

    // MARK: - Navigation history

    /// Files visited in this window, oldest first. Capped so a long reading
    /// session doesn't retain every node it ever touched.
    private static let historyLimit = 100
    private(set) var backStack: [FileNode] = []
    private(set) var forwardStack: [FileNode] = []
    /// Set while `goBack`/`goForward` move the selection, so the `didSet` above
    /// doesn't record the move as a new destination.
    private var isRestoringHistory = false

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = selectedFile { forwardStack.append(current) }
        show(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selectedFile { backStack.append(current) }
        show(next)
    }

    private func show(_ node: FileNode) {
        // Prefer the live node: a link jump can replace the tree, and the one on
        // the stack is then a detached object the sidebar wouldn't highlight.
        let inTree = findNode(path: node.id, in: rootNode)
        isRestoringHistory = true
        selectedFile = inTree ?? node
        isRestoringHistory = false
        if let inTree { expandPathTo(node: inTree) }
    }

    private func clearHistory() {
        backStack.removeAll()
        forwardStack.removeAll()
    }

    // MARK: - In-document links

    /// Open a file linked from the document on screen, selecting it in the
    /// sidebar when the tree already has it. `heading` is the link's `#fragment`.
    func navigate(to url: URL, heading: String? = nil) {
        let target = url.standardizedFileURL
        let path = target.path(percentEncoded: false)

        if let node = findNode(path: path, in: rootNode) {
            expandPathTo(node: node)
            selectedFile = node
            addRecentItem(target)
        } else {
            // Outside the loaded tree, or hidden by the strict filter. Open it
            // the way a double-click would — that also pulls in its folder.
            openSingleFile(target)
        }

        if let heading, !heading.isEmpty {
            pendingHeading = PendingHeading(filePath: path, heading: heading)
        }
    }

    /// Load a folder into the sidebar as the current local source. Shared by the
    /// Open dialog and by links that point at a directory.
    func openDirectory(_ url: URL) {
        directoryContextTask?.cancel()
        selectedSourceID = "local"
        isSingleFileMode = false
        searchQuery = ""
        searchResults = []
        SettingsStore.shared.lastLocalFolderPath = url.path(percentEncoded: false)
        addRecentItem(url)
        loadDirectory(url)
        startWatching(url)
    }

    init() {
        // NOTE: source detection is deliberately NOT done here. Scanning the
        // candidate directories (a large ~/.claude can hold thousands of session
        // files) is slow, and doing it synchronously in init blocks app launch —
        // including the fast path where the user just double-clicked a single
        // .md file. Detection runs off the main thread via `detectSourcesIfNeeded()`,
        // called from the view's `.task` once the window is on screen.
        selectedSourceID = SettingsStore.shared.lastSelectedSourceID
        if let raw = SettingsStore.shared.appThemeRaw,
           let saved = AppTheme(rawValue: raw) {
            appTheme = saved
        }
        showAllJsonFiles = SettingsStore.shared.showAllJsonFiles
    }

    /// Detect available sources off the main thread, then — only on a normal
    /// launch where no file was opened directly — auto-select the saved or first
    /// source. Runs at most once; safe to call from the view's `.task`.
    func detectSourcesIfNeeded() async {
        guard !didStartDetection else { return }
        didStartDetection = true

        // Run the filesystem scan off the main actor so launch isn't blocked.
        let detected = await Task.detached(priority: .userInitiated) {
            AISource.detectAllAvailable()
        }.value

        availableSources = detected
        isDetectingSources = false

        // If a file was opened directly (double-click / drag / URL scheme), it
        // already populated `rootNode` — don't override it with a default source.
        if rootNode == nil && !isSingleFileMode {
            restoreOrAutoSelect()
        }
    }

    /// True for sandboxed (Mac App Store) builds that haven't yet been granted
    /// access to a host folder. SidebarView shows a "Grant access" empty state in
    /// this case. Always false for the direct-distribution build.
    var needsSandboxGrant: Bool {
        #if os(macOS)
        return !isDetectingSources
            && BookmarkStore.isSandboxed
            && !BookmarkStore.shared.hasAnyGrant
            && availableSources.isEmpty
        #else
        return false
        #endif
    }

    /// Trigger the system folder picker, persist a security-scoped bookmark, and
    /// refresh the detected sources. Called from the sidebar's grant button.
    @MainActor
    func grantSandboxAccess() {
        #if os(macOS)
        guard BookmarkStore.shared.requestAccess() != nil else { return }
        // After the grant, re-detect available sources so the sidebar repopulates.
        availableSources = AISource.detectAllAvailable()
        if let first = availableSources.first {
            selectSource(first)
        }
        #endif
    }

    /// Cycle between Standard and Eye-Care.
    func toggleAppTheme() {
        appTheme = (appTheme == .standard) ? .eyeCare : .standard
    }

    /// Ask DetailView to open the find-in-file bar.
    func requestFindInFile() {
        findInFileToken &+= 1
    }

    /// Refresh the available sources list (after adding/removing custom sources)
    func refreshSources() {
        let previousID = selectedSourceID
        availableSources = AISource.detectAllAvailable()
        // If current selection was removed, clear it
        if let id = previousID, !availableSources.contains(where: { $0.id == id }) {
            selectedSourceID = nil
        }
    }

    /// Add a custom AI source directory via folder picker
    #if os(macOS)
    func addCustomSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an AI memory/config directory"
        panel.prompt = "Add Source"

        if panel.runModal() == .OK, let url = panel.url {
            AISource.addCustomSource(path: url.path(percentEncoded: false))
            refreshSources()
            // Auto-select the newly added source
            if let newSource = availableSources.first(where: { $0.id == "custom:\(url.path(percentEncoded: false))" }) {
                selectSource(newSource)
            }
        }
    }
    #endif

    /// Remove a custom AI source
    func removeCustomSource(_ source: AISource) {
        guard source.isCustom else { return }
        AISource.removeCustomSource(path: source.path)
        refreshSources()
        // If we removed the selected source, select something else
        if selectedSourceID == source.id {
            selectedSourceID = nil
            if let first = availableSources.first {
                selectSource(first)
            } else {
                rootNode = nil
                rootURL = nil
            }
        }
    }

    /// Called on launch to restore last source or pick the first available
    func restoreOrAutoSelect() {
        // Try to restore the saved source
        if let savedID = selectedSourceID,
           let source = availableSources.first(where: { $0.id == savedID }) {
            selectSource(source)
            return
        }

        #if os(macOS)
        // Try to restore local folder
        if selectedSourceID == "local",
           let savedPath = SettingsStore.shared.lastLocalFolderPath {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                loadDirectory(url)
                startWatching(url)
                return
            }
        }
        #endif

        // Fallback: pick first available source
        if let first = availableSources.first {
            selectSource(first)
            return
        }
    }

    func selectSource(_ source: AISource) {
        selectedSourceID = source.id
        isSingleFileMode = false
        searchQuery = ""
        searchResults = []
        loadDirectory(source.url)
        startWatching(source.url)
    }

    #if os(macOS)
    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .json
        ]
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder or file"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            if url.hasDirectoryPath {
                openDirectory(url)
            } else {
                // Single file selected - open directly without loading directory tree
                openSingleFile(url)
            }
        }
    }
    #endif

    /// Open a single file directly without loading directory tree
    func openSingleFile(_ url: URL) {
        directoryContextTask?.cancel()
        addRecentItem(url)
        selectedSourceID = "local"
        isSingleFileMode = true
        searchQuery = ""
        searchResults = []

        // Stop previous file watching
        #if os(macOS)
        if let stream = activeStream {
            FileWatcher.stopStream(stream)
            activeStream = nil
        }
        #endif

        let fileNode = FileNode(url: url, isDirectory: false)
        rootURL = url
        rootNode = FileNode(url: url.deletingLastPathComponent(), isDirectory: true, children: [fileNode])
        rootNode?.isExpanded = true
        selectedFile = fileNode
        todayFileNode = nil

        // Watch the single file's parent for changes
        startWatching(url.deletingLastPathComponent())

        loadDirectoryContext(around: url)
    }

    /// After a direct file open, load the file's surrounding directory into the
    /// sidebar so siblings are browsable without a trip back to Finder. Runs
    /// off the main actor so the double-click fast path stays instant; when the
    /// tree is ready, leaving single-file mode makes the sidebar appear. If the
    /// parent isn't readable (a sandboxed double-click grants access to the
    /// file only), the single-file view stays as-is.
    private var directoryContextTask: Task<Void, Never>?

    /// Folders the user declined to grant when offered the directory-context
    /// prompt. Device-local (like the bookmarks themselves), so plain defaults.
    private static let declinedFolderGrantsKey = "directoryContextDeclinedPaths_v1"

    private func loadDirectoryContext(around url: URL) {
        let parent = url.deletingLastPathComponent()
        let strict = !showAllJsonFiles
        directoryContextTask = Task { [weak self] in
            // Let the just-opened file paint first. The walk itself runs off the
            // main actor (see FileTreeBuilder.scan) — a folder with thousands of
            // entries used to freeze the window here for as long as the walk took.
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled else { return }
            // Bail if the user has moved on (switched source, opened a folder…).
            guard self.isSingleFileMode,
                  self.selectedFile?.url.standardizedFileURL.path == url.standardizedFileURL.path else { return }

            // A sandboxed double-click grants access to the file only, not its
            // folder. When the folder isn't readable, ask once per folder —
            // that's the whole feature for files outside the granted roots.
            if !Self.canReadDirectory(parent) {
                #if os(macOS)
                guard BookmarkStore.isSandboxed else { return }
                let parentPath = parent.path(percentEncoded: false)
                var declined = UserDefaults.standard.stringArray(forKey: Self.declinedFolderGrantsKey) ?? []
                guard !declined.contains(parentPath) else { return }
                let granted = BookmarkStore.shared.requestAccess(
                    prompt: "Show Folder",
                    message: "Grant access to “\(parent.lastPathComponent)” so the sidebar can show the files next to the one you opened. Pick a parent folder to cover more notes at once — AIMR only reads files locally.",
                    startAt: parent
                )
                if granted == nil {
                    declined.append(parentPath)
                    UserDefaults.standard.set(declined, forKey: Self.declinedFolderGrantsKey)
                    return
                }
                // The user may have granted an unrelated folder; re-probe and
                // re-check that they haven't moved on while the panel was up.
                guard Self.canReadDirectory(parent),
                      self.isSingleFileMode,
                      self.selectedFile?.url.standardizedFileURL.path == url.standardizedFileURL.path else { return }
                #else
                return
                #endif
            }
            self.isLoadingTree = true
            let snapshot = await FileTreeBuilder.scan(at: parent, strictFiltering: strict)
            self.isLoadingTree = false

            // A big folder can take a while to walk. Re-check that the user is
            // still looking at this file before replacing what's on screen.
            guard let snapshot, !Task.isCancelled,
                  self.isSingleFileMode,
                  self.selectedFile?.url.standardizedFileURL.path == url.standardizedFileURL.path else { return }

            let tree = FileTreeBuilder.materialize(snapshot)
            tree.isExpanded = true
            // The strict filter only keeps known memory files — the opened file
            // itself may not qualify. Keep it visible regardless.
            if self.findNode(url: url, in: tree) == nil {
                tree.children = (tree.children ?? []) + [FileNode(url: url, isDirectory: false)]
            }
            self.rootURL = parent
            self.rootNode = tree
            self.selectedFile = self.findNode(url: url, in: tree)
            self.isSingleFileMode = false
        }
    }

    /// A directory counts as readable only if we can actually enumerate it —
    /// `isReadableFile` alone can pass while a sandbox denies the listing.
    nonisolated private static func canReadDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    func loadDirectory(_ url: URL) {
        directoryContextTask?.cancel()
        treeLoadTask?.cancel()
        // A different tree means the back stack points at files that are no
        // longer reachable from the sidebar. Start over.
        clearHistory()
        rootURL = url
        // Drop the previous directory's tree immediately: showing the old
        // folder's files under the new folder's name is worse than showing
        // the loading state for a moment.
        rootNode = nil
        selectedFile = nil
        todayFileNode = nil

        let strict = !showAllJsonFiles
        isLoadingTree = true
        treeLoadTask = Task { [weak self] in
            let snapshot = await FileTreeBuilder.scan(at: url, strictFiltering: strict)
            guard let self else { return }
            self.isLoadingTree = false
            // Bail if this load was superseded while the walk ran.
            guard let snapshot, !Task.isCancelled, self.rootURL == url else { return }
            let tree = FileTreeBuilder.materialize(snapshot)
            tree.isExpanded = true
            self.rootNode = tree
        }
    }

    /// Rebuild the current tree using the current filter mode. Preserves
    /// expanded directories and the selected file when possible.
    func rebuildCurrentTree() {
        guard let rootURL else { return }
        treeLoadTask?.cancel()

        let strict = !showAllJsonFiles
        isLoadingTree = true
        treeLoadTask = Task { [weak self] in
            let snapshot = await FileTreeBuilder.scan(at: rootURL, strictFiltering: strict)
            guard let self else { return }
            self.isLoadingTree = false
            guard let snapshot, !Task.isCancelled, self.rootURL == rootURL else { return }
            let fresh = FileTreeBuilder.materialize(snapshot)
            if let existing = self.rootNode {
                // In-place reconcile (see handleFileSystemChange) — the show-all toggle
                // adds/removes many files but keeps expansion and selection stable.
                FileTreeBuilder.merge(into: existing, from: fresh)
            } else {
                fresh.isExpanded = true
                self.rootNode = fresh
            }
        }
    }

    // MARK: - URL Scheme

    func handleURL(_ url: URL) {
        guard url.scheme == "aimemoryreader" else { return }

        // aimemoryreader://repo?url=https://github.com/owner/name
        // aimemoryreader://repo?owner=…&name=…&ref=…&path=docs/guide.md&heading=Setup
        if url.host == "repo" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ key: String) -> String? {
                items.first { $0.name == key }?.value?.nilIfEmpty
            }
            var repo: GitHubRepoRef?
            if let raw = value("url") ?? value("repo") {
                repo = GitHubRepoRef.parse(raw)
            } else if let owner = value("owner"), let name = value("name") {
                repo = GitHubRepoRef.parse("\(owner)/\(name)")
            }
            guard var repo else { return }
            if let ref = value("ref") { repo.ref = ref }
            if let subpath = value("subpath") { repo.subpath = subpath }
            pendingRepoLink = RepoDeepLink(
                repo: repo,
                documentPath: value("path"),
                heading: value("heading")
            )
            return
        }

        if url.host == "open" || url.path.isEmpty {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            if let path = queryItems.first(where: { $0.name == "path" })?.value {
                // Reject path traversal and non-absolute paths from URL-scheme callers.
                guard !path.contains("..") && path.hasPrefix("/") else { return }
                let fileURL = URL(fileURLWithPath: path).standardizedFileURL
                guard fileURL.path.hasPrefix("/") && !fileURL.path.contains("..") else { return }
                let heading = queryItems.first(where: { $0.name == "heading" })?.value

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    openSingleFile(fileURL)
                    if let heading, !heading.isEmpty {
                        pendingHeading = PendingHeading(
                            filePath: fileURL.path(percentEncoded: false),
                            heading: heading
                        )
                    }
                }
            }
        }
    }

    // MARK: - Search

    func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        // Single file mode: search within that file only
        if isSingleFileMode, let file = selectedFile {
            isSearching = true
            let query = searchQuery
            let fileURL = file.url
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let results = SearchService.searchInFile(query: query, fileURL: fileURL)
                DispatchQueue.main.async {
                    self?.searchResults = results
                    self?.isSearching = false
                }
            }
            return
        }

        // Directory mode: search within the loaded directory
        guard let rootURL else {
            searchResults = []
            return
        }
        isSearching = true
        let query = searchQuery
        let url = rootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = SearchService.search(query: query, in: url)
            DispatchQueue.main.async {
                self?.searchResults = results
                self?.isSearching = false
            }
        }
    }

    func selectSearchResult(_ result: SearchResult) {
        // Find or create matching node in file tree
        if let node = findNode(url: result.fileNode.url, in: rootNode) {
            expandPathTo(node: node)
            selectedFile = node
        } else {
            // Node not in tree, use the search result's node directly
            selectedFile = result.fileNode
        }
    }

    // MARK: - File Watching

    private func startWatching(_ url: URL) {
        #if os(macOS)
        // Stop previous stream
        if let stream = activeStream {
            FileWatcher.stopStream(stream)
            activeStream = nil
        }
        if let obs = fsObserver {
            NotificationCenter.default.removeObserver(obs)
            fsObserver = nil
        }

        let watcher = FileWatcher(path: url.path(percentEncoded: false))
        activeStream = watcher.startStream()

        fsObserver = NotificationCenter.default.addObserver(
            forName: .fileWatcherDidDetectChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fileSystemEventArrived()
            }
        }
        #endif
    }

    #if os(macOS)
    /// Nudge the open document to re-check its own timestamp at most this often.
    private static let staleCheckThrottle: TimeInterval = 0.3
    /// Quiet period before re-walking the directory.
    private static let treeDebounce: Duration = .milliseconds(500)
    /// …and the longest the re-walk may be postponed by continuous events.
    private static let treeMaxWait: TimeInterval = 2.0

    private func fileSystemEventArrived() {
        let now = Date()

        // Two independent halves, deliberately not sharing a timer. They used to:
        // both waited on one trailing debounce that every new event cancelled, so
        // on a source that is *always* being written — `~/.claude/projects`, where
        // agents append to session logs continuously, which is this app's main
        // source — the timer never reached its deadline and neither half ever ran.
        // The sidebar went stale for as long as the agent kept working.
        if now.timeIntervalSince(lastReloadSignal) >= Self.staleCheckThrottle {
            lastReloadSignal = now
            fileChangeToken &+= 1
        }

        // The directory re-walk keeps its trailing debounce, but with a ceiling
        // for the same reason — continuous writes must not postpone it forever.
        if debounceStartedAt == nil { debounceStartedAt = now }
        debounceTask?.cancel()
        if let started = debounceStartedAt, now.timeIntervalSince(started) >= Self.treeMaxWait {
            debounceStartedAt = nil
            handleFileSystemChange()
            return
        }
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.treeDebounce)
            guard !Task.isCancelled, let self else { return }
            self.debounceStartedAt = nil
            self.handleFileSystemChange()
        }
    }
    #endif

    #if os(macOS)
    private func handleFileSystemChange() {
        guard let rootURL else { return }

        // Re-walk off the main actor. On a busy source like ~/.claude/projects
        // this fires every time an agent appends to a session log, so doing it
        // on the main thread meant a stall per burst of writes. No loading
        // state here on purpose — the tree on screen stays valid meanwhile.
        treeLoadTask?.cancel()
        let strict = !showAllJsonFiles
        treeLoadTask = Task { [weak self] in
            let snapshot = await FileTreeBuilder.scan(at: rootURL, strictFiltering: strict)
            guard let self, let snapshot, !Task.isCancelled, self.rootURL == rootURL else { return }
            let fresh = FileTreeBuilder.materialize(snapshot)
            if let existing = self.rootNode {
                // Reconcile in place: reuse existing FileNode objects where paths match,
                // so the sidebar List — and its selection, expansion, and scroll — is
                // never torn down on a filesystem event. Only genuine adds/removes mutate
                // the tree. (Previously this replaced rootNode wholesale and the List was
                // force-recreated via `.id(fileChangeToken)`, which caused selection
                // flicker and ghost highlights on busy sources like ~/.claude.)
                FileTreeBuilder.merge(into: existing, from: fresh)
            } else {
                fresh.isExpanded = true
                self.rootNode = fresh
            }
        }
    }
    #endif

    // MARK: - Recent Items

    /// Max entries kept in the sidebar "Recent" list (files and folders combined).
    private static let recentItemsLimit = 10

    func removeRecentItem(_ path: String) {
        var items = recentItems
        items.removeAll { $0 == path }
        recentItems = items
    }

    /// Record a just-opened file or folder at the top of the recent list (most-recent
    /// first, de-duplicated). Covers every open path — Finder double-click, drag-drop,
    /// the Open dialog, and the URL scheme all funnel through here or `openSingleFile`.
    func addRecentItem(_ url: URL) {
        let path = url.path(percentEncoded: false)
        guard !path.isEmpty else { return }
        var items = recentItems
        items.removeAll { $0 == path }
        items.insert(path, at: 0)
        if items.count > Self.recentItemsLimit {
            items = Array(items.prefix(Self.recentItemsLimit))
        }
        recentItems = items
    }

    // MARK: - Today File

    /// If the source has a memory/YYYY-MM-DD.md for today, find it in the tree and highlight it
    private func autoSelectTodayFile(for source: AISource) {
        guard let todayURL = source.todayMemoryFile else { return }
        if let node = findNode(url: todayURL, in: rootNode) {
            todayFileNode = node
            expandPathTo(node: node)
            selectedFile = node
        }
    }

    // MARK: - Tree Navigation

    func findNode(url: URL, in node: FileNode?) -> FileNode? {
        guard let node else { return nil }
        if node.url == url { return node }
        if let children = node.children {
            for child in children {
                if let found = findNode(url: url, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    /// Same lookup keyed on the filesystem path. A URL built by appending a
    /// relative link to a folder is not `==` to the one the tree walk produced
    /// even when both name the same file; `FileNode.id` is the decoded path, so
    /// comparing that is what actually matches.
    func findNode(path: String, in node: FileNode?) -> FileNode? {
        guard let node else { return nil }
        if node.id == path { return node }
        if let children = node.children {
            for child in children {
                if let found = findNode(path: path, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    func expandPathTo(node: FileNode) {
        guard let root = rootNode else { return }
        _ = expandPathTo(target: node.url, in: root)
    }

    @discardableResult
    private func expandPathTo(target: URL, in node: FileNode) -> Bool {
        if node.url == target { return true }
        if let children = node.children {
            for child in children {
                if expandPathTo(target: target, in: child) {
                    node.isExpanded = true
                    return true
                }
            }
        }
        return false
    }
}
