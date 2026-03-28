#if os(macOS)
import MarkdownUI
import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let file = appState.selectedFile, !file.isDirectory {
                MarkdownDetailView(fileNode: file, fileChangeToken: appState.fileChangeToken)
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.document")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Select a markdown file to view")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MarkdownDetailView: View {
    @Environment(AppState.self) private var appState
    let fileNode: FileNode
    let fileChangeToken: Int
    @State private var rawContent: String?
    @State private var editableContent: String = ""
    @State private var loadError: String?
    @State private var tocEntries: [TOCEntry] = []
    @State private var sections: [MarkdownSection] = []
    @State private var activeEntryID: String?
    @State private var showTOC = true
    @State private var scrollTarget: String?
    @State private var isEditMode = false
    @State private var saveState: SaveState = .idle
    @State private var autoSaveTask: Task<Void, Never>?

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()

            if let error = loadError {
                errorView(error)
            } else if rawContent != nil {
                if isEditMode {
                    editorView
                } else {
                    readView
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileNode.id) {
            await loadFile()
        }
        .onChange(of: fileChangeToken) { _, _ in
            // Only reload from disk if we're not in edit mode (avoid overwriting edits)
            if !isEditMode {
                Task { await loadFile() }
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorManualSave)) { _ in
            if isEditMode {
                saveIfNeeded()
            }
        }
        .onChange(of: appState.pendingURLHeading) { _, heading in
            if let heading, !heading.isEmpty {
                // Find matching TOC entry and scroll to it
                if let entry = tocEntries.first(where: { $0.title.localizedCaseInsensitiveContains(heading) }) {
                    scrollTarget = entry.id
                }
                appState.pendingURLHeading = nil
            }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.accentColor)
            Text(fileNode.name)
                .font(.headline)
            Spacer()

            // Save state indicator
            if isEditMode {
                saveIndicator
            }

            if let raw = rawContent {
                Text("\(raw.count) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Edit/Preview toggle button
            Button {
                toggleEditMode()
            } label: {
                Image(systemName: isEditMode ? "eye" : "pencil")
                    .foregroundColor(isEditMode ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(isEditMode ? "Switch to Read mode (⌘E)" : "Switch to Edit mode (⌘E)")
            .keyboardShortcut("e", modifiers: .command)

            if !tocEntries.isEmpty && !isEditMode {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTOC.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(showTOC ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showTOC ? "Hide Table of Contents" : "Show Table of Contents")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Save Indicator

    @ViewBuilder
    private var saveIndicator: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Saving…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Saved")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Editor View

    private var editorView: some View {
        MarkdownEditorView(text: $editableContent) { newText in
            scheduleAutoSave()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Read View (existing)

    /// The parent directory of the current file, used to resolve relative paths
    private var fileBaseURL: URL {
        fileNode.url.deletingLastPathComponent()
    }

    private var readView: some View {
        HStack(spacing: 0) {
            // Main markdown content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Markdown(section.content)
                                .markdownTheme(.memoryReader)
                                .markdownCodeSyntaxHighlighter(.splash)
                                .markdownImageProvider(.localFile(basePath: fileBaseURL))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 2)
                                .id(section.id)
                                .onAppear {
                                    if tocEntries.contains(where: { $0.id == section.id }) {
                                        activeEntryID = section.id
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 16)
                    .environment(\.openURL, OpenURLAction { url in
                        return Self.handleLocalLink(url: url, baseURL: fileBaseURL)
                    })
                }
                .onChange(of: scrollTarget) { _, newValue in
                    if let target = newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }
            }

            // TOC sidebar on right
            if showTOC && !tocEntries.isEmpty {
                Divider()
                TOCSidebarView(
                    entries: tocEntries,
                    activeEntryID: activeEntryID
                ) { entry in
                    activeEntryID = entry.id
                    scrollTarget = entry.id
                }
            }
        }
    }

    // MARK: - Edit Mode Toggle

    private func toggleEditMode() {
        if isEditMode {
            // Switching from Edit → Read: save first, then update rendered view
            saveIfNeeded()
            rawContent = editableContent
            tocEntries = TOCParser.parse(editableContent)
            sections = MarkdownSplitter.split(editableContent, entries: tocEntries)
        } else {
            // Switching from Read → Edit: load content into editor
            editableContent = rawContent ?? ""
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditMode.toggle()
        }
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await MainActor.run {
                    saveIfNeeded()
                }
            }
        }
    }

    private func saveIfNeeded() {
        guard isEditMode else { return }
        let content = editableContent
        guard content != rawContent else { return }

        saveState = .saving
        do {
            try content.write(to: fileNode.url, atomically: true, encoding: .utf8)
            rawContent = content
            saveState = .saved

            // Clear "saved" indicator after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                if saveState == .saved {
                    withAnimation {
                        saveState = .idle
                    }
                }
            }
        } catch {
            // On save error, keep the state but show briefly
            saveState = .idle
        }
    }

    // MARK: - Manual Save (⌘S)

    func manualSave() {
        saveIfNeeded()
    }

    // MARK: - Link Handling

    /// Handle links: open local file links with default app, web links in browser
    static func handleLocalLink(url: URL, baseURL: URL) -> OpenURLAction.Result {
        // Web links — let the system handle them
        if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
            return .systemAction
        }

        // Resolve the local path
        let resolvedURL: URL
        if url.scheme == "file" {
            resolvedURL = url
        } else {
            // Relative path or bare path
            let path = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            if path.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: path)
            } else {
                resolvedURL = baseURL.appendingPathComponent(path)
            }
        }

        // Open with default system app
        let fileURL = resolvedURL.isFileURL ? resolvedURL : URL(fileURLWithPath: resolvedURL.path)
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            NSWorkspace.shared.open(fileURL)
            return .handled
        }

        return .systemAction
    }

    // MARK: - Load File

    private func loadFile() async {
        loadError = nil
        isEditMode = false
        saveState = .idle
        do {
            let data = try Data(contentsOf: fileNode.url)
            guard let text = String(data: data, encoding: .utf8) else {
                loadError = "Unable to decode file as UTF-8"
                return
            }
            rawContent = text
            editableContent = text
            tocEntries = TOCParser.parse(text)
            sections = MarkdownSplitter.split(text, entries: tocEntries)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Failed to load file")
                .font(.title3)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plain code syntax highlighter (fallback)

struct PlainCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        Text(code)
    }
}

extension CodeSyntaxHighlighter where Self == PlainCodeSyntaxHighlighter {
    static var plain: PlainCodeSyntaxHighlighter { PlainCodeSyntaxHighlighter() }
}
#endif
