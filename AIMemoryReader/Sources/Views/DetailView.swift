#if os(macOS)
import MarkdownUI
import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        ThemePalette.resolve(appState.appTheme, colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if let file = appState.selectedFile, !file.isDirectory {
                MarkdownDetailView(fileNode: file, fileChangeToken: appState.fileChangeToken)
            } else {
                placeholderView
            }
        }
        .environment(\.themePalette, palette)
        .background(palette.isEyeCare ? AnyShapeStyle(palette.background) : AnyShapeStyle(Color.clear))
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.document")
                .font(.system(size: 56))
                .foregroundColor((palette.isEyeCare ? palette.secondaryText : Color.secondary).opacity(0.6))
            Text("Select a file to view")
                .font(.title2)
                .foregroundColor(palette.isEyeCare ? palette.secondaryText : .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MarkdownDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
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

    // MARK: - Find in page
    @State private var isFindActive = false
    @State private var findQuery: String = ""
    @State private var findMatches: [FindMatch] = []
    @State private var findCurrentIndex: Int = 0

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()

            if isFindActive {
                FileFindBar(
                    query: Binding(
                        get: { findQuery },
                        set: { newValue in
                            findQuery = newValue
                            recomputeFindMatches()
                        }
                    ),
                    matchCount: findMatches.count,
                    currentIndex: findCurrentIndex,
                    onPrevious: gotoPreviousMatch,
                    onNext: gotoNextMatch,
                    onClose: closeFind
                )
            }

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
        .onChange(of: appState.findInFileToken) { _, _ in
            openFind()
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorManualSave)) { _ in
            if isEditMode {
                saveIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            if let content = rawContent {
                let filename = fileNode.url.deletingPathExtension().lastPathComponent
                let baseURL = fileNode.url.deletingLastPathComponent()
                PDFExporter.exportToPDF(markdownText: content, defaultFilename: filename, baseURL: baseURL)
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
            Image(systemName: fileNode.isJSON ? "curlybraces" : "doc.text")
                .foregroundColor(palette.accent)
            Text(fileNode.name)
                .font(.headline)
                .foregroundColor(palette.isEyeCare ? palette.text : .primary)
            Spacer()

            // Save state indicator
            if isEditMode {
                saveIndicator
            }

            if let raw = rawContent {
                Text("\(raw.count) chars")
                    .font(.caption)
                    .foregroundColor(palette.isEyeCare ? palette.secondaryText : .secondary)
            }

            // Edit/Preview toggle button
            Button {
                toggleEditMode()
            } label: {
                Image(systemName: isEditMode ? "eye" : "pencil")
                    .foregroundColor(isEditMode ? palette.accent
                                                 : (palette.isEyeCare ? palette.secondaryText : .secondary))
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
                        .foregroundColor(showTOC ? palette.accent
                                                 : (palette.isEyeCare ? palette.secondaryText : .secondary))
                }
                .buttonStyle(.plain)
                .help(showTOC ? "Hide Table of Contents" : "Show Table of Contents")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(palette.isEyeCare ? AnyShapeStyle(palette.secondaryBackground) : AnyShapeStyle(.bar))
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
        let currentMatchSectionID: String? = findMatches.indices.contains(findCurrentIndex)
            ? findMatches[findCurrentIndex].sectionID
            : nil
        let matchingSectionIDs: Set<String> = Set(findMatches.map(\.sectionID))

        return HStack(spacing: 0) {
            // Main markdown content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Markdown(section.content)
                                .markdownTheme(.memoryReader(palette: palette))
                                .markdownCodeSyntaxHighlighter(.splash)
                                .markdownImageProvider(.localFile(basePath: fileBaseURL))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 2)
                                .background(findHighlightBackground(for: section.id,
                                                                     current: currentMatchSectionID,
                                                                     all: matchingSectionIDs))
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
                .background(palette.isEyeCare ? AnyShapeStyle(palette.background) : AnyShapeStyle(Color.clear))
                .onChange(of: scrollTarget) { _, newValue in
                    if let target = newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }
                .onChange(of: findCurrentIndex) { _, _ in
                    if let id = currentMatchSectionID {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
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

    /// Background for a section when find-in-page is active.
    @ViewBuilder
    private func findHighlightBackground(for sectionID: String,
                                          current: String?,
                                          all: Set<String>) -> some View {
        if sectionID == current {
            RoundedRectangle(cornerRadius: 6)
                .fill(palette.findCurrent)
                .padding(.horizontal, 10)
        } else if all.contains(sectionID) {
            RoundedRectangle(cornerRadius: 6)
                .fill(palette.findMatch)
                .padding(.horizontal, 10)
        } else {
            Color.clear
        }
    }

    // MARK: - Edit Mode Toggle

    private func toggleEditMode() {
        if isEditMode {
            // Switching from Edit → Read: save first, then update rendered view
            saveIfNeeded()
            rawContent = editableContent
            if fileNode.isJSON {
                tocEntries = []
                sections = [MarkdownSection(id: "json-content", content: "```json\n\(editableContent)\n```")]
            } else {
                tocEntries = TOCParser.parse(editableContent)
                sections = MarkdownSplitter.split(editableContent, entries: tocEntries)
            }
        } else {
            // Switching from Read → Edit: load content into editor
            editableContent = rawContent ?? ""
        }
        // Close our in-page find bar whenever mode flips — edit mode uses the
        // NSTextView system Find Bar instead, and we don't want both visible.
        closeFind()
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

    // MARK: - Find in File

    private func openFind() {
        guard rawContent != nil else { return }
        if isEditMode {
            // Edit mode delegates to NSTextView's built-in Find Bar.
            NotificationCenter.default.post(name: .editorShowFindBar, object: nil)
            return
        }
        isFindActive = true
        recomputeFindMatches()
    }

    private func closeFind() {
        isFindActive = false
        findQuery = ""
        findMatches = []
        findCurrentIndex = 0
    }

    private func recomputeFindMatches() {
        guard isFindActive, let raw = rawContent, !findQuery.isEmpty else {
            findMatches = []
            findCurrentIndex = 0
            return
        }
        let matches = FindMatcher.compute(in: raw, query: findQuery, sections: sections)
        findMatches = matches
        if matches.isEmpty {
            findCurrentIndex = 0
        } else {
            findCurrentIndex = min(findCurrentIndex, matches.count - 1)
        }
    }

    private func gotoNextMatch() {
        guard !findMatches.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex + 1) % findMatches.count
    }

    private func gotoPreviousMatch() {
        guard !findMatches.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex - 1 + findMatches.count) % findMatches.count
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

            if fileNode.isJSON {
                let displayText = Self.prettyPrintJSON(text) ?? text
                rawContent = displayText
                editableContent = displayText
                tocEntries = []
                sections = [MarkdownSection(id: "json-content", content: "```json\n\(displayText)\n```")]
            } else {
                rawContent = text
                editableContent = text
                tocEntries = TOCParser.parse(text)
                sections = MarkdownSplitter.split(text, entries: tocEntries)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func prettyPrintJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else { return nil }
        return prettyString
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
