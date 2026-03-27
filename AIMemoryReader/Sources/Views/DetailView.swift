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
    let fileNode: FileNode
    let fileChangeToken: Int
    @State private var rawContent: String?
    @State private var loadError: String?
    @State private var tocEntries: [TOCEntry] = []
    @State private var sections: [MarkdownSection] = []
    @State private var activeEntryID: String?
    @State private var showTOC = true
    @State private var scrollTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()

            if let error = loadError {
                errorView(error)
            } else if rawContent != nil {
                HStack(spacing: 0) {
                    // Main markdown content
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(sections) { section in
                                    Markdown(section.content)
                                        .markdownTheme(.memoryReader)
                                        .markdownCodeSyntaxHighlighter(.splash)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 2)
                                        .id(section.id)
                                        .onAppear {
                                            // Update active TOC entry when section scrolls into view
                                            if tocEntries.contains(where: { $0.id == section.id }) {
                                                activeEntryID = section.id
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 16)
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileNode.id) {
            await loadFile()
        }
        .onChange(of: fileChangeToken) { _, _ in
            Task { await loadFile() }
        }
    }

    private var titleBar: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.accentColor)
            Text(fileNode.name)
                .font(.headline)
            Spacer()
            if let raw = rawContent {
                Text("\(raw.count) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !tocEntries.isEmpty {
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

    private func loadFile() async {
        loadError = nil
        do {
            let data = try Data(contentsOf: fileNode.url)
            guard let text = String(data: data, encoding: .utf8) else {
                loadError = "Unable to decode file as UTF-8"
                return
            }
            rawContent = text
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
