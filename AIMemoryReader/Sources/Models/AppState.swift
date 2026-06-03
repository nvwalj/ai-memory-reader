import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var rootNode: FileNode?
    var selectedFile: FileNode?
    var rootURL: URL?

    /// When true, a single file was opened directly (not a directory)
    var isSingleFileMode: Bool = false

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
    #endif

    /// Incremented on each file-system change so views can react
    var fileChangeToken: Int = 0

    // MARK: - Suggested Rules (v0.5)
    /// Cached scan results, sorted by frequency desc.
    var suggestedRules: [RuleSuggestion] = []
    /// Controls the Suggested Rules sheet visibility.
    var showSuggestedRulesSheet: Bool = false

    // MARK: - Recent Folders

    var recentFolders: [String] {
        get { SettingsStore.shared.recentFolders }
        set { SettingsStore.shared.recentFolders = newValue }
    }

    // MARK: - URL Scheme handling

    var pendingURLPath: String?
    var pendingURLHeading: String?

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
                selectedSourceID = "local"
                isSingleFileMode = false
                SettingsStore.shared.lastLocalFolderPath = url.path(percentEncoded: false)
                addRecentFolder(url.path(percentEncoded: false))
                loadDirectory(url)
                startWatching(url)
            } else {
                // Single file selected - open directly without loading directory tree
                openSingleFile(url)
            }
        }
    }
    #endif

    /// Open a single file directly without loading directory tree
    func openSingleFile(_ url: URL) {
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
    }

    func loadDirectory(_ url: URL) {
        rootURL = url
        rootNode = FileTreeBuilder.buildTree(at: url, strictFiltering: !showAllJsonFiles)
        rootNode?.isExpanded = true
        selectedFile = nil
        todayFileNode = nil
    }

    /// Rebuild the current tree using the current filter mode. Preserves
    /// expanded directories and the selected file when possible.
    func rebuildCurrentTree() {
        guard let rootURL else { return }
        let fresh = FileTreeBuilder.buildTree(at: rootURL, strictFiltering: !showAllJsonFiles)
        if let existing = rootNode {
            // In-place reconcile (see handleFileSystemChange) — the show-all toggle
            // adds/removes many files but keeps expansion and selection stable.
            FileTreeBuilder.merge(into: existing, from: fresh)
        } else {
            rootNode = fresh
            rootNode?.isExpanded = true
        }
    }

    // MARK: - URL Scheme

    func handleURL(_ url: URL) {
        guard url.scheme == "aimemoryreader" else { return }

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
                    if let heading {
                        pendingURLHeading = heading
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
                // Debounce rapid FSEvents — wait 0.5s of quiet before rebuilding
                self?.debounceTask?.cancel()
                self?.debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.handleFileSystemChange()
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private func handleFileSystemChange() {
        guard let rootURL else { return }

        let fresh = FileTreeBuilder.buildTree(at: rootURL, strictFiltering: !showAllJsonFiles)
        if let existing = rootNode {
            // Reconcile in place: reuse existing FileNode objects where paths match,
            // so the sidebar List — and its selection, expansion, and scroll — is
            // never torn down on a filesystem event. Only genuine adds/removes mutate
            // the tree. (Previously this replaced rootNode wholesale and the List was
            // force-recreated via `.id(fileChangeToken)`, which caused selection
            // flicker and ghost highlights on busy sources like ~/.claude.)
            FileTreeBuilder.merge(into: existing, from: fresh)
        } else {
            rootNode = fresh
            rootNode?.isExpanded = true
        }

        // Tell the detail view to reload the open file's content from disk.
        fileChangeToken += 1
    }
    #endif

    // MARK: - Recent Folders

    func removeRecentFolder(_ path: String) {
        var folders = recentFolders
        folders.removeAll { $0 == path }
        recentFolders = folders
    }

    private func addRecentFolder(_ path: String) {
        var folders = recentFolders
        folders.removeAll { $0 == path }
        folders.insert(path, at: 0)
        if folders.count > 5 {
            folders = Array(folders.prefix(5))
        }
        recentFolders = folders
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
