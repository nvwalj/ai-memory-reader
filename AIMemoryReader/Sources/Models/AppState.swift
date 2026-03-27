import SwiftUI

@MainActor
@Observable
final class AppState {
    var rootNode: FileNode?
    var selectedFile: FileNode?
    var rootURL: URL?

    /// When true, a single file was opened directly (not a directory)
    var isSingleFileMode: Bool = false

    var availableSources: [AISource] = []
    var selectedSourceID: String? {
        didSet {
            UserDefaults.standard.set(selectedSourceID, forKey: "lastSelectedSourceID")
        }
    }

    /// Today's memory file node, if the current source has one
    var todayFileNode: FileNode?

    // MARK: - Search

    var searchQuery: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var focusSearch: Bool = false

    // MARK: - File Watching

    private var activeStream: FSEventStreamRef?
    private var fsObserver: Any?

    /// Incremented on each file-system change so views can react
    var fileChangeToken: Int = 0

    // MARK: - Recent Folders

    var recentFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentFolders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentFolders") }
    }

    init() {
        availableSources = AISource.detectAvailable()
        selectedSourceID = UserDefaults.standard.string(forKey: "lastSelectedSourceID")
    }

    /// Called on launch to restore last source or pick the first available
    func restoreOrAutoSelect() {
        // Try to restore the saved source
        if let savedID = selectedSourceID,
           let source = availableSources.first(where: { $0.id == savedID }) {
            selectSource(source)
            return
        }

        // Try to restore local folder
        if selectedSourceID == "local",
           let savedPath = UserDefaults.standard.string(forKey: "lastLocalFolderPath") {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                loadDirectory(url)
                startWatching(url)
                return
            }
        }

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
        autoSelectTodayFile(for: source)
        startWatching(source.url)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder or markdown file"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            if url.hasDirectoryPath {
                selectedSourceID = "local"
                isSingleFileMode = false
                UserDefaults.standard.set(url.path(percentEncoded: false), forKey: "lastLocalFolderPath")
                addRecentFolder(url.path(percentEncoded: false))
                loadDirectory(url)
                startWatching(url)
            } else {
                // Single file selected - open directly without loading directory tree
                openSingleFile(url)
            }
        }
    }

    /// Open a single .md file directly without loading directory tree
    func openSingleFile(_ url: URL) {
        selectedSourceID = "local"
        isSingleFileMode = true
        searchQuery = ""
        searchResults = []

        // Stop previous file watching
        if let stream = activeStream {
            FileWatcher.stopStream(stream)
            activeStream = nil
        }

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
        rootNode = FileTreeBuilder.buildTree(at: url)
        rootNode?.isExpanded = true
        selectedFile = nil
        todayFileNode = nil
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
                self?.handleFileSystemChange()
            }
        }
    }

    private func handleFileSystemChange() {
        guard let rootURL else { return }

        // Remember current selection
        let previousSelectedURL = selectedFile?.url

        // Rebuild file tree
        rootNode = FileTreeBuilder.buildTree(at: rootURL)
        rootNode?.isExpanded = true

        // Re-detect today file
        if let sourceID = selectedSourceID,
           let source = availableSources.first(where: { $0.id == sourceID }) {
            autoSelectTodayFile(for: source)
        }

        // Try to restore selection
        if let prevURL = previousSelectedURL,
           let node = findNode(url: prevURL, in: rootNode) {
            expandPathTo(node: node)
            selectedFile = node
        }

        // Increment change token so detail view can reload
        fileChangeToken += 1
    }

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
