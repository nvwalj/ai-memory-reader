#if os(macOS)
import SwiftUI

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // AI Sources section
            aiSourcesSection

            Divider()

            // Search bar
            searchBar

            Divider()

            // Search results or file tree
            if !appState.searchQuery.isEmpty {
                searchResultsList
            } else if let root = appState.rootNode {
                List(selection: Bindable(appState).selectedFile) {
                    if let children = root.children {
                        ForEach(children) { node in
                            FileNodeView(node: node)
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                emptyState
            }
        }
        .safeAreaInset(edge: .top) {
            headerView
        }
        .frame(minWidth: 220)
        .onChange(of: appState.focusSearch) { _, newValue in
            if newValue {
                isSearchFocused = true
                appState.focusSearch = false
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("AI Memory Reader")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var aiSourcesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sources")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    appState.addCustomSource()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add custom AI source directory")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ForEach(appState.availableSources) { source in
                AISourceRow(source: source, isSelected: appState.selectedSourceID == source.id)
                    .onTapGesture {
                        appState.selectSource(source)
                    }
                    .if(source.isCustom) { view in
                        view.contextMenu {
                            Button(role: .destructive) {
                                appState.removeCustomSource(source)
                            } label: {
                                Label("Remove Source", systemImage: "trash")
                            }
                        }
                    }
            }

            // Local Files option
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 22)
                Text("Local Files…")
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                appState.selectedSourceID == "local"
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .onTapGesture {
                appState.openFolder()
            }

            // Recent Folders
            if !appState.recentFolders.isEmpty {
                recentFoldersSection
            }

            if appState.availableSources.isEmpty {
                Text("No AI sources detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 8)
    }

    private var recentFoldersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ForEach(appState.recentFolders, id: \.self) { path in
                let url = URL(fileURLWithPath: path)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 18)
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedSourceID = "local"
                    UserDefaults.standard.set(path, forKey: "lastLocalFolderPath")
                    appState.loadDirectory(url)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        appState.removeRecentFolder(path)
                    } label: {
                        Label("Remove from Recent", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField(appState.isSingleFileMode ? "Find in file…" : "Search markdown files…", text: Bindable(appState).searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onSubmit {
                    appState.performSearch()
                }
                .onChange(of: appState.searchQuery) { _, newValue in
                    if newValue.isEmpty {
                        appState.searchResults = []
                    } else {
                        appState.performSearch()
                    }
                }

            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                    appState.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchResultsList: some View {
        Group {
            if appState.isSearching {
                VStack {
                    Spacer()
                    ProgressView("Searching…")
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.searchResults) { result in
                        SearchResultRow(result: result)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectSearchResult(result)
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No folder opened")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Select an AI source or ⌘O to open a folder")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 11))
                Text(result.fileNode.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            Text(result.matchedLine)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text("Line \(result.lineNumber)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AI Source Row

struct AISourceRow: View {
    let source: AISource
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: source.iconName)
                .font(.system(size: 14))
                .foregroundColor(source.color)
                .frame(width: 22)
            Text(source.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            if source.todayMemoryFile != nil {
                Circle()
                    .fill(source.color)
                    .frame(width: 8, height: 8)
                    .help("Today's memory file available")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            isSelected
                ? source.color.opacity(0.15)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
    }
}

// MARK: - File Node View

struct FileNodeView: View {
    @Environment(AppState.self) private var appState
    let node: FileNode

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: Bindable(node).isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileNodeView(node: child)
                    }
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .foregroundColor(.primary)
            }
        } else {
            Label {
                HStack {
                    Text(node.name)
                        .lineLimit(1)
                    if appState.todayFileNode == node {
                        Text("Today")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            } icon: {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
            }
            .tag(node)
        }
    }
}
#endif
