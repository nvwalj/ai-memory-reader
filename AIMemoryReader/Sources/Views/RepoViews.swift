#if os(iOS)
import MarkdownUI
import SwiftUI

/// Everything the iOS app can navigate to. One typed path for the whole app so a
/// link inside a document can push another document, which nested
/// `NavigationLink` destinations can't do.
enum AppRoute: Hashable, Codable {
    case repoFolder(repoID: String, path: String)
    case repoDocument(repoID: String, path: String)
    case settings
}

/// Where the user was last reading, restored on next launch.
///
/// A reader that forgets its place every time it's backgrounded is one you stop
/// using on a phone, where the app is evicted constantly. Settings is
/// deliberately not restored — nobody wants to reopen into a preferences screen.
enum NavigationRestore {
    private static let key = "iosNavigationPath_v1"

    static func save(_ path: [AppRoute]) {
        let restorable = path.filter { $0 != .settings }
        guard let data = try? JSONEncoder().encode(restorable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [AppRoute] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let path = try? JSONDecoder().decode([AppRoute].self, from: data)
        else { return [] }
        return path
    }
}

// MARK: - Home

struct RepoLibraryView: View {
    @Environment(RepoLibrary.self) private var library
    @Environment(AppState.self) private var appState
    @Binding var path: [AppRoute]
    @State private var showAddSheet = false
    @State private var showDocumentPicker = false

    var body: some View {
        List {
            if library.repos.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Repositories") {
                    ForEach(library.repos) { repo in
                        Button {
                            path.append(.repoFolder(repoID: repo.id, path: repo.subpath ?? ""))
                        } label: {
                            RepoRow(repo: repo)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { library.remove(atOffsets: $0) }
                    .onMove { library.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Section("On This Device") {
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Open a File…", systemImage: "folder")
                }
                // Opening a file loads its folder, so its siblings are listed
                // here too rather than the one file you happened to tap.
                if let children = appState.rootNode?.children, !children.isEmpty {
                    ForEach(children) { node in
                        iOSFileNodeRow(node: node)
                    }
                } else if let file = appState.selectedFile, !file.isDirectory {
                    NavigationLink {
                        iOSDetailView(fileNode: file)
                    } label: {
                        Label(file.name, systemImage: "doc.text")
                    }
                }
            }
        }
        .navigationTitle("AI Memory Reader")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !library.repos.isEmpty { EditButton() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add repository")
            }
        }
        .sheet(isPresented: $showAddSheet) { AddRepoSheet() }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in appState.openSingleFile(url) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No repositories yet")
                .font(.headline)
            Text("Add a GitHub repository to read its Markdown, JSON and config files — `CLAUDE.md`, `AGENTS.md`, docs, memory notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Repository") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct RepoRow: View {
    @Environment(RepoLibrary.self) private var library
    let repo: GitHubRepoRef

    var body: some View {
        let session = library.session(for: repo)
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.displayName(defaultBranch: session.info?.defaultBranch))
                    .font(.body)
                    .foregroundStyle(.primary)
                if let description = session.info?.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if session.fileCount > 0 {
                    Text("\(session.fileCount) documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .task { await session.load() }
    }
}

// MARK: - Add

struct AddRepoSheet: View {
    @Environment(RepoLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("owner/repo or a github.com link", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit { submit() }
                } footer: {
                    Text("Also accepts a link to a branch or folder, like github.com/owner/repo/tree/main/docs.")
                }

                if let error = library.addError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if !GitHubTokenStore.hasToken {
                    Section {
                        Text("Public repositories work with no setup. For private ones, add a token in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if library.isAdding {
                        ProgressView()
                    } else {
                        Button("Add") { submit() }
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        let text = input
        Task {
            if await library.add(text) != nil { dismiss() }
        }
    }
}

// MARK: - Browsing a repository

struct RepoBrowserView: View {
    @Environment(RepoLibrary.self) private var library
    @Binding var path: [AppRoute]
    let repo: GitHubRepoRef
    /// Repo-relative folder path. The repo's own `subpath` for the top level.
    let folderPath: String

    @State private var query = ""

    private var isRoot: Bool { folderPath == (repo.subpath ?? "") }

    var body: some View {
        let session = library.session(for: repo)
        Group {
            switch session.status {
            case .idle, .loading:
                ProgressView("Loading \(repo.slug)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failure(message, session: session)
            case .ready:
                listing(session)
            }
        }
        .navigationTitle(isRoot ? repo.name : (folderPath as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await session.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        if let url = repo.webURL {
                            Link(destination: url) {
                                Label("Open on GitHub", systemImage: "safari")
                            }
                        }
                        Toggle(isOn: Bindable(library).memoryFilesOnly) {
                            Label("AI Memory Files Only", systemImage: "brain")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await session.load() }
    }

    @ViewBuilder
    private func listing(_ session: RepoSession) -> some View {
        let folder = session.root?.find(path: folderPath) ?? session.root
        let children = folder?.children ?? []
        let matches = searchResults(session)

        List {
            if let warning = session.warning, isRoot {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !query.isEmpty {
                Section("\(matches.count) matching files") {
                    ForEach(matches) { node in
                        Button {
                            path.append(.repoDocument(repoID: repo.id, path: node.path))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(node.name, systemImage: icon(for: node))
                                Text(node.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if children.isEmpty {
                Section {
                    Text(session.root?.allFiles.isEmpty == true
                         ? "No readable documents in this repository."
                         : "This folder is empty.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(children) { node in
                        Button {
                            path.append(node.isDirectory
                                        ? .repoFolder(repoID: repo.id, path: node.path)
                                        : .repoDocument(repoID: repo.id, path: node.path))
                        } label: {
                            HStack {
                                Label(node.name, systemImage: icon(for: node))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if node.isDirectory {
                                    Text("\(node.allFiles.count)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: isRoot ? "Search \(repo.name)" : "Search this repository"
        )
        .refreshable { await session.refresh(silent: true) }
    }

    /// Filenames first, then anything whose path contains the query — a phone
    /// screen can't afford to bury the file you named.
    private func searchResults(_ session: RepoSession) -> [RepoNode] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let root = session.root else { return [] }
        let all = root.allFiles
        let byName = all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        let byPath = all.filter {
            !$0.name.localizedCaseInsensitiveContains(trimmed)
                && $0.path.localizedCaseInsensitiveContains(trimmed)
        }
        return byName + byPath
    }

    private func failure(_ message: String, session: RepoSession) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await session.refresh() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func icon(for node: RepoNode) -> String {
        if node.isDirectory { return "folder" }
        if node.isJSON { return "curlybraces" }
        return "doc.text"
    }
}

// MARK: - Reading a document

struct RepoDocumentView: View {
    @Environment(RepoLibrary.self) private var library
    @Binding var path: [AppRoute]
    let repo: GitHubRepoRef
    let documentPath: String

    @State private var sections: [MarkdownSection] = []
    @State private var tocEntries: [TOCEntry] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var scrollTarget: String?
    @State private var linkError: String?
    @State private var showTOC = false

    private var name: String { (documentPath as NSString).lastPathComponent }

    var body: some View {
        let session = library.session(for: repo)
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                errorView(loadError, session: session)
            } else {
                reader
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !tocEntries.isEmpty {
                        Button {
                            showTOC = true
                        } label: {
                            Label("Table of Contents", systemImage: "list.bullet")
                        }
                    }
                    if let url = githubURL {
                        Link(destination: url) {
                            Label("Open on GitHub", systemImage: "safari")
                        }
                        ShareLink(item: url) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showTOC) {
            NavigationStack {
                List(tocEntries) { entry in
                    Button {
                        scrollTarget = entry.id
                        showTOC = false
                    } label: {
                        Text(entry.title)
                            .padding(.leading, CGFloat((entry.level - 1) * 12))
                            .foregroundStyle(.primary)
                    }
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if let linkError {
                Text(linkError)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .task(id: documentPath) { await load(session) }
    }

    private var reader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        MarkdownSectionView(section: section, imageBaseURL: imageBaseURL)
                            .id(section.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .environment(\.openURL, OpenURLAction { (url: URL) -> OpenURLAction.Result in
                    handleLink(url) ? .handled : .systemAction
                })
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
    }

    // MARK: - Loading

    private func load(_ session: RepoSession) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard let node = session.root?.find(path: documentPath) else {
            loadError = "\(documentPath) is no longer in this repository."
            return
        }
        do {
            let text = try await session.documentText(for: node)
            if node.isJSON {
                let pretty = Self.prettyPrintJSON(text) ?? text
                tocEntries = []
                sections = Self.jsonSections(pretty)
            } else {
                let display = MarkdownDisplayPrep.prepare(text)
                tocEntries = TOCParser.parse(display)
                sections = MarkdownSplitter.split(display, entries: tocEntries)
            }
            consumePendingHeading(session)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            loadError = (error as? GitHubError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Links

    private func handleLink(_ url: URL) -> Bool {
        let session = library.session(for: repo)
        guard let root = session.root else { return false }
        switch RepoLinkResolver.resolve(rawLink: url.absoluteString, fromDocumentAt: documentPath, in: root) {
        case .web:
            return false
        case .anchor(let fragment):
            jump(to: fragment)
        case .document(let target, let heading):
            if target == documentPath {
                if let heading { jump(to: heading) }
            } else {
                // Hand the anchor to the document being pushed — it can only be
                // matched once that file's own headings are parsed.
                if let heading { session.pendingHeading = (path: target, heading: heading) }
                path.append(.repoDocument(repoID: repo.id, path: target))
            }
        case .folder(let target):
            path.append(.repoFolder(repoID: repo.id, path: target))
        case .missing(let text):
            show("Not in this repository: \(text)")
        }
        return true
    }

    /// Take the scroll request left by whichever document linked here — but only
    /// the one addressed to this file.
    private func consumePendingHeading(_ session: RepoSession) {
        guard let pending = session.pendingHeading, pending.path == documentPath else { return }
        session.pendingHeading = nil
        jump(to: pending.heading)
    }

    private func jump(to fragment: String) {
        guard let entry = TOCParser.entry(for: fragment, in: tocEntries) else {
            show("No heading “\(fragment)” in this file.")
            return
        }
        scrollTarget = entry.id
    }

    private func show(_ message: String) {
        withAnimation { linkError = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { linkError = nil }
        }
    }

    private var githubURL: URL? {
        let session = library.session(for: repo)
        return URL(string: "https://github.com/\(repo.owner)/\(repo.name)/blob/\(session.resolvedRef)/\(documentPath)")
    }

    /// The document's own folder on the raw CDN, so `![](home.png)` next to a
    /// README loads. Private repositories can't be read from this host, so their
    /// images stay blank — the text is what matters there.
    private var imageBaseURL: URL? {
        let session = library.session(for: repo)
        let folder = (documentPath as NSString).deletingLastPathComponent
        var base = "https://raw.githubusercontent.com/\(repo.owner)/\(repo.name)/\(session.resolvedRef)/"
        if !folder.isEmpty { base += "\(folder)/" }
        return URL(string: base)
    }

    private func errorView(_ message: String, session: RepoSession) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await load(session) } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - JSON

    private static func prettyPrintJSON(_ text: String) -> String? {
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return nil
    }

    /// Same chunking rule as macOS: MarkdownUI builds a code block as one `Text`
    /// per token, and a few thousand chained `Text`s overflow the main thread's
    /// stack while SwiftUI resolves them.
    private static func jsonSections(_ text: String) -> [MarkdownSection] {
        let linesPerChunk = 30
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count > linesPerChunk else {
            return [MarkdownSection(id: "json-content", content: "```json\n\(text)\n```")]
        }
        var sections: [MarkdownSection] = []
        var index = 0
        while index < lines.count {
            let end = min(index + linesPerChunk, lines.count)
            let chunk = lines[index..<end].joined(separator: "\n")
            sections.append(MarkdownSection(id: "json-chunk-\(sections.count)", content: "```json\n\(chunk)\n```"))
            index = end
        }
        return sections
    }
}

// MARK: - Settings

struct GitHubSettingsView: View {
    @Environment(RepoLibrary.self) private var library
    @State private var token = ""
    @State private var savedNote: String?
    @State private var cacheSize: Int64 = 0

    var body: some View {
        Form {
            Section {
                SecureField("ghp_… or github_pat_…", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save Token") { save() }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    if GitHubTokenStore.hasToken {
                        Button("Remove", role: .destructive) {
                            GitHubTokenStore.token = nil
                            token = ""
                            savedNote = "Token removed."
                        }
                    }
                }
                if let savedNote {
                    Text(savedNote).font(.footnote).foregroundStyle(.secondary)
                } else if let redacted = GitHubTokenStore.redacted {
                    Text("Stored: \(redacted)").font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("GitHub Token (optional)")
            } footer: {
                Text("Only needed for private repositories, and to raise the API limit from 60 to 5,000 requests an hour. A classic token needs the `repo` scope; a fine-grained one needs Contents: Read. It is stored in this device's Keychain, never synced, and never sent anywhere but api.github.com.")
            }

            Section {
                Toggle("AI Memory Files Only", isOn: Bindable(library).memoryFilesOnly)
            } footer: {
                Text("Narrows every repository to files that look like AI memory or config — Markdown, JSONL transcripts, and known filenames like CLAUDE.md or config.yaml — instead of every readable document.")
            }

            Section {
                LabeledContent("Downloaded", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                Button("Clear Downloaded Files", role: .destructive) {
                    Task {
                        await GitHubCache.shared.clearAll()
                        cacheSize = await GitHubCache.shared.sizeOnDisk()
                    }
                }
            } header: {
                Text("Offline Copies")
            } footer: {
                Text("Files you open are kept so they read without a connection. Clearing them doesn't remove your repositories.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { cacheSize = await GitHubCache.shared.sizeOnDisk() }
    }

    private func save() {
        GitHubTokenStore.token = token
        token = ""
        savedNote = "Saved. Private repositories are now readable."
    }
}
#endif
