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
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            if let error = loadError {
                errorView(error)
            } else if let raw = rawContent {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // TOC at top of document
                            if !tocEntries.isEmpty {
                                TOCView(entries: tocEntries) { entry in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(entry.anchor, anchor: .top)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                            }

                            // Markdown content with anchored headings
                            MarkdownWithAnchors(content: raw, tocEntries: tocEntries)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
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

/// Renders markdown content with scroll anchors on headings
struct MarkdownWithAnchors: View {
    let content: String
    let tocEntries: [TOCEntry]

    var body: some View {
        Markdown(content)
            .markdownTheme(.memoryReader)
            .markdownCodeSyntaxHighlighter(.splash)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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
