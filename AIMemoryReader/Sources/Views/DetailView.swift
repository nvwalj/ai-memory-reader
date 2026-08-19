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
    /// The file exactly as it is on disk. Drives edit mode, saving, and the
    /// character count — never the rendering.
    @State private var rawContent: String?
    /// What the renderers see: `rawContent` after `MarkdownDisplayPrep` — wiki
    /// links expanded, HTML comments hidden. Kept separate so edit mode and
    /// saving still work on the file's real text.
    @State private var displayContent: String = ""
    @State private var editableContent: String = ""
    @State private var loadError: String?
    /// Transient message shown when a link points at nothing.
    @State private var linkError: String?
    @State private var linkErrorTask: Task<Void, Never>?
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
    @State private var findCurrentIndex: Int = 0
    /// Pre-rendered attributed document used when the find bar is open. We
    /// re-render when the source or palette changes, not on every keystroke.
    @State private var renderedForFind: ReadableMarkdownRenderer.Output?
    /// NSRanges (in the rendered plain text) of all matches for the current query.
    @State private var findMatchRanges: [NSRange] = []

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
                    matchCount: findMatchRanges.count,
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
        .overlay(alignment: .bottom) {
            if let linkError {
                Text(linkError)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12))
                    )
                    .padding(.bottom, 24)
                    .transition(.opacity)
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
        .onChange(of: palette.isEyeCare) { _, _ in
            // Palette shifted — rebuild the find-mode rendering so colors match.
            if isFindActive, rawContent != nil {
                ensureRenderedForFind()
                recomputeFindMatches()
            }
        }
        .onChange(of: fileNode.id) { _, _ in
            // File changed — drop cached find rendering so the next find pass
            // reparses from the new content.
            renderedForFind = nil
        }
        .onDisappear {
            autoSaveTask?.cancel()
            linkErrorTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorManualSave)) { _ in
            if isEditMode {
                saveIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            if rawContent != nil {
                let filename = fileNode.url.deletingPathExtension().lastPathComponent
                let baseURL = fileNode.url.deletingLastPathComponent()
                PDFExporter.exportToPDF(markdownText: displayContent, defaultFilename: filename, baseURL: baseURL)
            }
        }
        .onChange(of: appState.pendingHeading) { _, _ in
            // Fires for a jump inside the file already on screen; a jump to a
            // different file is consumed by `loadFile` once its TOC exists.
            consumePendingHeading()
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

    @ViewBuilder
    private var readView: some View {
        HStack(spacing: 0) {
            mainReadingPane

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

    @ViewBuilder
    private var mainReadingPane: some View {
        if isFindActive, let rendered = renderedForFind {
            // When the find bar is open, switch to NSTextView-backed rendering
            // so matches can be highlighted at character granularity.
            FindableReadableView(
                baseAttributed: rendered.attributed,
                matchRanges: findMatchRanges,
                currentIndex: findCurrentIndex,
                palette: palette,
                onLink: { handleLink($0) }
            )
            .background(palette.isEyeCare
                        ? AnyShapeStyle(palette.background)
                        : AnyShapeStyle(Color.clear))
        } else {
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
                                .id(section.id)
                                .onAppear {
                                    if tocEntries.contains(where: { $0.id == section.id }) {
                                        activeEntryID = section.id
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 16)
                    .environment(\.openURL, OpenURLAction { (url: URL) -> OpenURLAction.Result in
                        handleLink(url) ? .handled : .systemAction
                    })
                }
                .background(palette.isEyeCare
                            ? AnyShapeStyle(palette.background)
                            : AnyShapeStyle(Color.clear))
                .onChange(of: scrollTarget) { _, newValue in
                    if let target = newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        scrollTarget = nil
                    }
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
            if fileNode.isJSON {
                displayContent = editableContent
                tocEntries = []
                sections = Self.makeJSONSections(editableContent)
            } else {
                let display = MarkdownDisplayPrep.prepare(editableContent)
                displayContent = display
                tocEntries = TOCParser.parse(display)
                sections = MarkdownSplitter.split(display, entries: tocEntries)
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
        ensureRenderedForFind()
        isFindActive = true
        recomputeFindMatches()
    }

    private func closeFind() {
        isFindActive = false
        findQuery = ""
        findMatchRanges = []
        findCurrentIndex = 0
        renderedForFind = nil
    }

    /// Build the `ReadableMarkdownRenderer` output lazily — only when the
    /// find bar opens — and reuse it across keystrokes.
    private func ensureRenderedForFind() {
        guard rawContent != nil else { return }
        renderedForFind = ReadableMarkdownRenderer.render(displayContent, palette: palette)
    }

    private func recomputeFindMatches() {
        guard isFindActive,
              let rendered = renderedForFind,
              !findQuery.isEmpty else {
            findMatchRanges = []
            findCurrentIndex = 0
            return
        }
        let ns = rendered.plain as NSString
        let fullLength = ns.length
        var ranges: [NSRange] = []
        var start = 0
        while start < fullLength {
            let searchRange = NSRange(location: start, length: fullLength - start)
            let r = ns.range(of: findQuery, options: .caseInsensitive, range: searchRange)
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            start = r.location + max(r.length, 1)
        }
        findMatchRanges = ranges
        if ranges.isEmpty {
            findCurrentIndex = 0
        } else {
            findCurrentIndex = min(findCurrentIndex, ranges.count - 1)
        }
    }

    private func gotoNextMatch() {
        guard !findMatchRanges.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex + 1) % findMatchRanges.count
    }

    private func gotoPreviousMatch() {
        guard !findMatchRanges.isEmpty else { return }
        findCurrentIndex = (findCurrentIndex - 1 + findMatchRanges.count) % findMatchRanges.count
    }

    // MARK: - Link Handling

    /// Route a clicked link. Anything that resolves to a file the reader can
    /// display stays inside the app; the rest goes to the system.
    /// Returns true when the app handled it and the system should stay out.
    private func handleLink(_ url: URL) -> Bool {
        switch LinkResolver.resolve(url, relativeTo: fileBaseURL) {
        case .web:
            return false

        case .anchor(let fragment):
            scrollToHeading(fragment)

        case .document(let fileURL, let heading):
            if fileURL.path(percentEncoded: false) == fileNode.url.path(percentEncoded: false) {
                // A link back into the file already open — just move.
                if let heading { scrollToHeading(heading) }
            } else {
                appState.navigate(to: fileURL, heading: heading)
            }

        case .directory(let directoryURL):
            appState.openDirectory(directoryURL)

        case .externalFile(let fileURL):
            NSWorkspace.shared.open(fileURL)

        case .missing(let text):
            showLinkError("No file named “\(text)” next to this one.")
        }
        return true
    }

    private func scrollToHeading(_ heading: String) {
        guard let entry = TOCParser.entry(for: heading, in: tocEntries) else {
            showLinkError("No heading “\(heading)” in this file.")
            return
        }
        activeEntryID = entry.id
        scrollTarget = entry.id
    }

    /// Consume a scroll request queued by `AppState.navigate` — but only the one
    /// addressed to this file, so the view showing the *previous* document
    /// doesn't eat a jump meant for the next one.
    private func consumePendingHeading() {
        guard let pending = appState.pendingHeading,
              pending.filePath == fileNode.url.path(percentEncoded: false),
              rawContent != nil else { return }
        appState.pendingHeading = nil
        scrollToHeading(pending.heading)
    }

    private func showLinkError(_ message: String) {
        linkErrorTask?.cancel()
        withAnimation { linkError = message }
        linkErrorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { linkError = nil }
        }
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
                let pretty = Self.prettyPrintJSON(text) ?? text
                rawContent = pretty
                displayContent = pretty
                editableContent = pretty
                tocEntries = []
                sections = Self.makeJSONSections(pretty)
            } else {
                let display = MarkdownDisplayPrep.prepare(text)
                rawContent = text
                displayContent = display
                editableContent = text
                tocEntries = TOCParser.parse(display)
                sections = MarkdownSplitter.split(display, entries: tocEntries)
            }
            // The TOC exists now, so a jump queued for this file can land.
            consumePendingHeading()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func prettyPrintJSON(_ text: String) -> String? {
        // Single-object JSON: fast path.
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        // NDJSON / JSONL — Claude's telemetry files use `.json` but contain one object per line.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return nil }
        var rendered: [String] = []
        rendered.reserveCapacity(lines.count)
        var parsedAny = false
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                rendered.append("// line \(idx + 1)\n\(prettyString)")
                parsedAny = true
            } else {
                rendered.append("// line \(idx + 1) (unparsed)\n\(trimmed)")
            }
        }
        return parsedAny ? rendered.joined(separator: "\n\n") : nil
    }

    /// Chunk large JSON into multiple MarkdownSections so LazyVStack can lazy-render.
    /// MarkdownUI's code-block view builds the text as Text + Text + Text… per token, which
    /// SwiftUI then resolves recursively. ~5000 chained Texts blows the main-thread stack
    /// (observed crash: `ConcatenatedTextStorage.resolve` recursing 5414 levels). Keep
    /// chunks small enough that a single section never produces that many Text nodes:
    /// ~30 lines / ~3000 chars is comfortably under the threshold even for dense JSON.
    private static func makeJSONSections(_ text: String) -> [MarkdownSection] {
        let linesPerChunk = 30
        let maxCharsPerChunk = 3_000
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count <= linesPerChunk && text.count <= maxCharsPerChunk {
            return [MarkdownSection(id: "json-content", content: "```json\n\(text)\n```")]
        }
        var sections: [MarkdownSection] = []
        var idx = 0
        while idx < lines.count {
            var end = min(idx + linesPerChunk, lines.count)
            var chunk = lines[idx..<end].joined(separator: "\n")
            // Hard cap on chunk size — guards against single mega-lines (e.g. minified JSON).
            while chunk.count > maxCharsPerChunk && end - idx > 1 {
                end -= 1
                chunk = lines[idx..<end].joined(separator: "\n")
            }
            // Last-resort: a single line longer than maxCharsPerChunk — break it by characters.
            if chunk.count > maxCharsPerChunk && end - idx == 1 {
                var remaining = chunk
                while !remaining.isEmpty {
                    let take = min(maxCharsPerChunk, remaining.count)
                    let upper = remaining.index(remaining.startIndex, offsetBy: take)
                    let piece = String(remaining[remaining.startIndex..<upper])
                    sections.append(MarkdownSection(id: "json-chunk-\(sections.count)", content: "```json\n\(piece)\n```"))
                    remaining = String(remaining[upper...])
                }
                idx = end
                continue
            }
            sections.append(MarkdownSection(id: "json-chunk-\(sections.count)", content: "```json\n\(chunk)\n```"))
            idx = end
        }
        return sections
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
