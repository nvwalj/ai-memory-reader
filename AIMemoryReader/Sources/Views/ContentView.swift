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
        VStack(spacing: 0) {
            if case let .available(version, tag, releaseURL, notes) = UpdateChecker.shared.state {
                UpdateBanner(version: version, tag: tag, url: releaseURL, notes: notes)
            }
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } detail: {
                DetailView()
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 800, minHeight: 500)
        .task {
            await UpdateChecker.shared.checkIfDue()
        }
        .task {
            // Detect AI sources off the main thread so launch (and the
            // double-click-a-file fast path) isn't blocked by directory scans.
            await appState.detectSourcesIfNeeded()
        }
        .onChange(of: appState.isSingleFileMode) { _, isSingle in
            columnVisibility = isSingle ? .detailOnly : .automatic
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(isPresented: Bindable(appState).showSuggestedRulesSheet) {
            SuggestedRulesView()
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
            appState.addRecentItem(first)
            appState.loadDirectory(first)
            return
        }

        // Filter to supported files only
        let supportedFiles = urls.filter { FileNode.isSupportedFile($0) }
        guard let firstFile = supportedFiles.first else { return }

        if supportedFiles.count == 1 {
            appState.openSingleFile(firstFile)
        } else {
            let parentDir = firstFile.deletingLastPathComponent()
            appState.selectedSourceID = "local"
            appState.isSingleFileMode = false
            appState.loadDirectory(parentDir)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let node = appState.findNode(url: firstFile, in: appState.rootNode) {
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
    @State private var library = RepoLibrary()
    @State private var path: [AppRoute] = []
    @State private var didRestore = false

    var body: some View {
        NavigationStack(path: $path) {
            RepoLibraryView(path: $path)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(library)
        .onChange(of: path) { _, newPath in
            guard didRestore else { return }
            NavigationRestore.save(newPath)
        }
        .task {
            // Restore after the first render, not as the initial `@State` value:
            // a NavigationStack that is born with a non-empty path drops it,
            // because its destinations aren't registered yet at that point.
            if !didRestore {
                let saved = NavigationRestore.load()
                if !saved.isEmpty { path = saved }
                didRestore = true
            }
            await appState.detectSourcesIfNeeded()
        }
        .onChange(of: appState.pendingRepoLink) { _, link in
            guard let link else { return }
            appState.pendingRepoLink = nil
            Task { await follow(link) }
        }
    }

    /// Turn a `aimemoryreader://repo?…` link into a navigation path, adding the
    /// repository first if it isn't in the list yet.
    private func follow(_ link: AppState.RepoDeepLink) async {
        var repo = library.repos.first { $0.owner == link.repo.owner && $0.name == link.repo.name }
        if repo == nil {
            repo = await library.add(link.repo.webURL?.absoluteString ?? link.repo.slug)
        }
        guard let repo else { return }

        let session = library.session(for: repo)
        await session.load()
        guard let document = link.documentPath, !document.isEmpty else {
            path = [.repoFolder(repoID: repo.id, path: repo.subpath ?? "")]
            return
        }
        if let heading = link.heading {
            session.pendingHeading = (path: document, heading: heading)
        }
        path = [
            .repoFolder(repoID: repo.id, path: repo.subpath ?? ""),
            .repoDocument(repoID: repo.id, path: document),
        ]
    }

    /// One switch for every push in the app. A typed path is what lets a link
    /// inside a document push the document it points at — nested
    /// `NavigationLink` destinations can only go one level at a time.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            GitHubSettingsView()
        case .repoFolder(let repoID, let folder):
            if let repo = library.repos.first(where: { $0.id == repoID }) {
                RepoBrowserView(path: $path, repo: repo, folderPath: folder)
            } else {
                missingRepo
            }
        case .repoDocument(let repoID, let document):
            if let repo = library.repos.first(where: { $0.id == repoID }) {
                RepoDocumentView(path: $path, repo: repo, documentPath: document)
            } else {
                missingRepo
            }
        }
    }

    private var missingRepo: some View {
        ContentUnavailableView(
            "Repository removed",
            systemImage: "shippingbox",
            description: Text("This repository is no longer in your list.")
        )
    }
}

/// A row for a local file or folder, used in the home screen's "On This Device"
/// section. Repository documents have their own row type in `RepoViews`.
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
            .json,
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
        .onChange(of: appState.pendingHeading) { _, _ in
            consumePendingHeading()
        }
    }

    private func consumePendingHeading() {
        guard let pending = appState.pendingHeading,
              pending.filePath == fileNode.url.path(percentEncoded: false),
              rawContent != nil else { return }
        appState.pendingHeading = nil
        if let entry = TOCParser.entry(for: pending.heading, in: tocEntries) {
            scrollTarget = entry.id
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

            if fileNode.isJSON {
                let displayText = Self.prettyPrintJSON(text) ?? text
                rawContent = displayText
                tocEntries = []
                sections = [MarkdownSection(id: "json-content", content: "```json\n\(displayText)\n```")]
            } else {
                let display = MarkdownDisplayPrep.prepare(text)
                rawContent = text
                tocEntries = TOCParser.parse(display)
                sections = MarkdownSplitter.split(display, entries: tocEntries)
            }
            consumePendingHeading()
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
}

import MarkdownUI

struct MarkdownSectionView: View {
    let section: MarkdownSection
    /// Where relative image URLs point. Set for repository documents so a
    /// README's screenshots load from GitHub's raw CDN; nil for local files,
    /// where relative images are already resolved on disk.
    ///
    /// Only the *image* base is set on purpose. Setting MarkdownUI's `baseURL`
    /// too would rewrite every relative link into an absolute github.com URL,
    /// and links between documents would open Safari instead of navigating.
    var imageBaseURL: URL? = nil

    var body: some View {
        Markdown(section.content, imageBaseURL: imageBaseURL)
            .markdownTheme(.memoryReader)
            .markdownCodeSyntaxHighlighter(.splash)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}
#endif
