import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        #if os(macOS)
        MacContentView()
        #else
        iOSContentView()
        #endif
    }
}

// MARK: - macOS Layout

#if os(macOS)
struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            if appState.rootNode == nil {
                appState.restoreOrAutoSelect()
            }
        }
        .onChange(of: appState.isSingleFileMode) { _, isSingle in
            columnVisibility = isSingle ? .detailOnly : .automatic
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                collectedURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            processDroppedURLs(collectedURLs)
        }
    }

    private func processDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let fm = FileManager.default
        var isDir: ObjCBool = false

        // Check if any URL is a directory
        if let first = urls.first,
           urls.count == 1,
           fm.fileExists(atPath: first.path(percentEncoded: false), isDirectory: &isDir),
           isDir.boolValue {
            // Single folder dropped — load as directory
            appState.selectedSourceID = "local"
            appState.isSingleFileMode = false
            appState.loadDirectory(first)
            return
        }

        // Filter to .md files only
        let mdFiles = urls.filter { $0.pathExtension.lowercased() == "md" }
        guard !mdFiles.isEmpty else { return }

        if mdFiles.count == 1 {
            // Single .md file — open in single file mode
            appState.openSingleFile(mdFiles[0])
        } else {
            // Multiple .md files — load the common parent directory
            let parentDir = mdFiles[0].deletingLastPathComponent()
            appState.selectedSourceID = "local"
            appState.isSingleFileMode = false
            appState.loadDirectory(parentDir)

            // Auto-select the first dropped file
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let node = appState.findNode(url: mdFiles[0], in: appState.rootNode) {
                    appState.selectedFile = node
                }
            }
        }
    }
}
#endif

// MARK: - iOS Layout

#if os(iOS)
struct iOSContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationStack {
            iOSFileListView()
                .navigationTitle("AI Memory Reader")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showDocumentPicker = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                    }
                }
                .sheet(isPresented: $showDocumentPicker) {
                    DocumentPickerView { url in
                        appState.openSingleFile(url)
                    }
                }
        }
        .onAppear {
            if appState.rootNode == nil {
                appState.restoreOrAutoSelect()
            }
        }
    }
}

struct iOSFileListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let root = appState.rootNode, let children = root.children, !children.isEmpty {
                List {
                    ForEach(children) { node in
                        iOSFileNodeRow(node: node)
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No files loaded")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Tap the folder icon to open a markdown file")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct iOSFileNodeRow: View {
    @Environment(AppState.self) private var appState
    let node: FileNode

    var body: some View {
        if node.isDirectory {
            DisclosureGroup {
                if let children = node.children {
                    ForEach(children) { child in
                        iOSFileNodeRow(node: child)
                    }
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
                    .foregroundStyle(.primary)
            }
        } else {
            NavigationLink {
                iOSDetailView(fileNode: node)
            } label: {
                Label {
                    HStack {
                        Text(node.name)
                            .lineLimit(1)
                        if appState.todayFileNode == node {
                            Text("Today")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - iOS Document Picker

import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType(filenameExtension: "md") ?? .plainText,
            .plainText
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            onPick(url)
            // Note: don't stop accessing here — we need it while viewing
        }
    }
}

// MARK: - iOS Detail View

struct iOSDetailView: View {
    @Environment(AppState.self) private var appState
    let fileNode: FileNode
    @State private var rawContent: String?
    @State private var loadError: String?
    @State private var tocEntries: [TOCEntry] = []
    @State private var sections: [MarkdownSection] = []
    @State private var scrollTarget: String?

    var body: some View {
        Group {
            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Failed to load file")
                        .font(.title3)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if rawContent != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                MarkdownSectionView(section: section)
                                    .id(section.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(fileNode.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: fileNode.id) {
            await loadFile()
        }
        .onChange(of: appState.pendingURLHeading) { _, heading in
            if let heading, !heading.isEmpty {
                if let entry = tocEntries.first(where: { $0.title.localizedCaseInsensitiveContains(heading) }) {
                    scrollTarget = entry.id
                }
                appState.pendingURLHeading = nil
            }
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
            sections = MarkdownSplitter.split(text, entries: tocEntries)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

import MarkdownUI

struct MarkdownSectionView: View {
    let section: MarkdownSection

    var body: some View {
        Markdown(section.content)
            .markdownTheme(.memoryReader)
            .markdownCodeSyntaxHighlighter(.splash)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}
#endif
