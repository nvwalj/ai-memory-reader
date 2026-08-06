import Foundation

/// A plain, `Sendable` snapshot of a directory subtree.
///
/// The filesystem walk is the expensive half of building a sidebar tree — on a
/// directory with thousands of entries it is seconds of syscalls. `FileNode` is
/// an `@Observable` class and therefore not `Sendable`, which is why the walk
/// used to run on the main actor and froze the UI. Scanning into this struct
/// crosses the isolation boundary safely, so the walk can happen off the main
/// actor and only the (cheap, allocation-only) `FileNode` construction runs on it.
struct FileScan: Sendable {
    let url: URL
    let isDirectory: Bool
    var children: [FileScan]?
}

enum FileTreeBuilder {
    /// Ceilings so a pathological directory — a synced drive, a `node_modules`
    /// neighbour, a Downloads folder with 100k files — degrades to a truncated
    /// tree instead of an open-ended walk. No real memory folder approaches
    /// these; they exist so "I double-clicked a file in the wrong place" stays
    /// survivable.
    static let maxEntries = 20_000
    static let maxDepth = 12

    /// Walk `url` off the main actor and return a snapshot of the tree.
    ///
    /// `nonisolated` + `async` means this does not run on the caller's actor,
    /// while still inheriting the surrounding task's cancellation — so
    /// navigating away mid-scan stops the work instead of finishing it into a
    /// result nobody wants. Returns `nil` when cancelled.
    nonisolated static func scan(at url: URL, strictFiltering: Bool = true) async -> FileScan? {
        var budget = maxEntries
        return scanNode(at: url, strict: strictFiltering, depth: 0, budget: &budget)
    }

    /// Synchronous walk, for callers already off the main actor (and for tests).
    /// Prefer `scan(at:strictFiltering:)` from UI code.
    nonisolated static func scanSync(at url: URL, strictFiltering: Bool = true) -> FileScan? {
        var budget = maxEntries
        return scanNode(at: url, strict: strictFiltering, depth: 0, budget: &budget)
    }

    private nonisolated static func scanNode(
        at url: URL,
        strict: Bool,
        depth: Int,
        budget: inout Int
    ) -> FileScan? {
        if Task.isCancelled { return nil }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else {
            return FileScan(url: url, isDirectory: false)
        }
        guard isDir.boolValue else {
            return FileScan(url: url, isDirectory: false)
        }
        // Depth guard: stop descending, but still report the directory so a deep
        // subtree isn't silently erased from the sidebar.
        guard depth < maxDepth else {
            return FileScan(url: url, isDirectory: true, children: [])
        }

        let contents = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Resolve `isDirectory` once per entry and filter before sorting. This
        // used to happen inside the sort comparator, which asked for the same
        // resource value O(n log n) times per directory instead of O(n).
        var entries: [(url: URL, isDirectory: Bool)] = []
        entries.reserveCapacity(contents.count)
        for child in contents {
            if Task.isCancelled { return nil }
            let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !childIsDir && !FileNode.isSupportedFile(child, strict: strict) { continue }
            entries.append((child, childIsDir))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }

        var children: [FileScan] = []
        children.reserveCapacity(entries.count)
        for entry in entries {
            if Task.isCancelled { return nil }
            guard budget > 0 else { break }
            budget -= 1

            if entry.isDirectory {
                guard let child = scanNode(at: entry.url, strict: strict, depth: depth + 1, budget: &budget) else {
                    return nil  // cancelled
                }
                // Directories that hold no matching files are noise — same rule
                // as before, applied during the walk rather than after it.
                if child.children?.isEmpty == false { children.append(child) }
            } else {
                children.append(FileScan(url: entry.url, isDirectory: false))
            }
        }

        return FileScan(url: url, isDirectory: true, children: children)
    }

    /// Turn a snapshot into the observable tree the sidebar renders. Allocation
    /// only — no filesystem access — so this is safe to run on the main actor.
    static func materialize(_ scan: FileScan) -> FileNode {
        guard scan.isDirectory, let children = scan.children else {
            return FileNode(url: scan.url, isDirectory: scan.isDirectory)
        }
        return FileNode(
            url: scan.url,
            isDirectory: true,
            children: children.map(materialize)
        )
    }

    /// Reconcile `existing` in place to match `fresh`, reusing existing FileNode
    /// objects wherever the path (id) matches — recursively. Preserving object
    /// identity keeps `isExpanded`, scroll position, and any `selectedFile`
    /// pointing into the tree intact, so the sidebar List is never torn down on a
    /// filesystem event. `existing.children` is reassigned only at the levels where
    /// the child set or order actually changed, so content-only events (e.g. an
    /// agent appending to a session log) cause zero observation churn.
    static func merge(into existing: FileNode, from fresh: FileNode) {
        guard existing.isDirectory else { return }
        let freshChildren = fresh.children ?? []

        var existingByID: [String: FileNode] = [:]
        for child in existing.children ?? [] { existingByID[child.id] = child }

        var reconciled: [FileNode] = []
        reconciled.reserveCapacity(freshChildren.count)
        for freshChild in freshChildren {
            if let keep = existingByID[freshChild.id], keep.isDirectory == freshChild.isDirectory {
                if keep.isDirectory { merge(into: keep, from: freshChild) }
                reconciled.append(keep)
            } else {
                reconciled.append(freshChild)
            }
        }

        if (existing.children ?? []).map(\.id) != reconciled.map(\.id) {
            existing.children = reconciled
        }
    }
}
